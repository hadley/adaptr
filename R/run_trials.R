#' Generate breakpoints and other values for printing progress
#'
#' Used internally. Generates breakpoints, messages, and 'batches' of trial
#' numbers to simulate when using [run_trials()] with the `progress` argument in
#' use. Breaks will be multiples of the number of `cores`, and repeated use of
#' the same values for breaks is avoided (if, e.g., the number of breaks times
#' the number of cores is not possible if few new trials are to be run). Inputs
#' are validated by [run_trials()].
#'
#' @inheritParams run_trials
#' @param prev_n_rep single integer, the previous number of simulations run (to
#'   add to the indices generated and used).
#' @param n_rep_new single integers, number of new simulations to run (i.e.,
#'   `n_rep` as supplied to [run_trials()] minus the number of previously run
#'   simulations if `grow` is used in [run_trials()]).
#'
#' @return List containing `breaks` (the number of patients at each break),
#'   `start_mess` and `prog_mess` (the first and subsequent progress messages'
#'   basis), and `batches` (a list with each entry corresponding to the
#'   simulation numbers in each batch).
#'
#' @keywords internal
#'
prog_breaks <- function(progress, prev_n_rep, n_rep_new, cores) {
  # Calculate the breakpoints and probabilities; only allow unique breakpoints
  prog_seq <- unique(c(seq(from = 0, to = 1, by = progress), 1))[-1] # Always end at 1, ignore first
  breaks <- rep(NA_real_, length(prog_seq))
  base_breaks <- prog_seq * n_rep_new
  # End at the final number of new simulations, regardless of the above
  breaks[length(breaks)] <- n_rep_new
  # For all other breakpoints, add as multiples of the number of cores
  valid_breaks <- (2:(n_rep_new - 1))[(2:(n_rep_new - 1)) %% cores == 0]
  for (i in seq_along(breaks)[-length(breaks)]) {
    # Select first valid break value which is a multiple of the number of cores
    tmp_break <- valid_breaks[valid_breaks >= base_breaks[i]][1]
    # Remove already used breaks
    valid_breaks <- valid_breaks[valid_breaks > tmp_break]
    breaks[i] <- tmp_break
  }
  # Match valid breaks and matching percentages
  breaks <- breaks[!is.na(breaks)]
  # Final proportion of breaks
  prog_prop <- rep(NA_real_, length(breaks) - 1)
  for (i in seq_along(prog_prop)) {
    prog_prop[i] <- prog_seq[which.min(abs(base_breaks - breaks[i]))]
  }
  # End with 1
  prog_prop <- c(prog_prop, 1)

  # Prepare message bases
  prog_mess <- paste0("run_trials: ", format(paste0(c(0, breaks), "/", n_rep_new), justify = "right"),
                      format(paste0(" (", round(c(0, prog_prop) * 100), "%)"), justify = "right"))

  # Prepare batches
  batches <- list()
  prog_prev_n <- 0
  for (i in seq_along(prog_prop)) {
    batches[[i]] <- ((prog_prev_n + 1):breaks[i]) + prev_n_rep
    prog_prev_n <- breaks[i]
  }

  # Return
  list(breaks = breaks,
       start_mess = paste(prog_mess[1], "[starting]"),
       prog_mess = prog_mess[-1],
       batches = batches)
}



#' Simulate single trial after setting seed
#'
#' Helper function to dispatch the running of several trials to [lapply()] or
#' [parallel::parLapply()], setting seeds correctly if a `base_seed` was used
#' when calling [run_trials()]. Used internally in calls by the [run_trials()]
#' function.
#'
#' @inheritParams run_trials
#' @param is vector of integers, the simulation numbers/indices.
#' @param trial_spec trial specification as provided by [setup_trial()],
#'   [setup_trial_binom()] or [setup_trial_norm()].
#' @param cl `NULL` (default) for running sequentially, otherwise a `parallel`
#'   cluster for parallel computation if `cores > 1`.
#'
#' @return Single trial simulation object, as described in [run_trial()].
#'
#' @keywords internal
#'
dispatch_trial_runs <- function(is, trial_spec, seeds, sparse, cores, cl = NULL) {
  common_args <- list(X = seeds[is], trial_spec = trial_spec, sparse = sparse)

  run_trial_seeds <- function(seeds, trial_spec, sparse) {
    if (!is.null(seeds)) {
      assign(".Random.seed", value = seeds, envir = globalenv())
    }
    run_trial(trial_spec, sparse = sparse)
  }

  if (cores == 1) {
    do.call(lapply, c(common_args, FUN = run_trial_seeds))
  } else {
    do.call(parLapply, c(common_args, fun = run_trial_seeds, cl = list(cl)))
  }
}



#' Simulate multiple trials
#'
#' This function conducts multiple simulations using a trial specification as
#' specified by [setup_trial()], [setup_trial_binom()] or [setup_trial_norm()].
#' This function essentially manages random seeds and runs multiple simulation
#' using [run_trial()] - additional details on individual simulations are
#' provided in that function's description. This function allows simulating
#' trials in parallel using multiple cores, automatically saving and re-loading
#' saved objects, and "growing" already saved simulation files (i.e., appending
#' additional simulations to the same file).
#'
#' @inheritParams run_trial
#' @param n_rep single integer; the number of simulations to run.
#' @param path single character string; if specified (defaults to `NULL`), files
#'   will be written to and  loaded from this path using the [saveRDS()] /
#'   [readRDS()] functions.
#' @param overwrite single logical; defaults to `FALSE`, in which case previous
#'   simulations saved in the same `path` will be re-loaded (if the same trial
#'   specification was used). If `TRUE`, the previous file is overwritten (even
#'   if the the same trial specification was not used). If `grow` is `TRUE`,
#'   this argument must be set to `FALSE`.
#' @param grow single logical; defaults to `FALSE`. If `TRUE` and a valid `path`
#'   to a valid previous file containing less simulations than `n_rep`, the
#'   additional number of simulations will be run (appropriately re-using the
#'   same `base_seed`, if specified) and appended to the same file.
#' @param cores `NULL` or single integer. If `NULL`, a default value/cluster set
#'   by [setup_cluster()] will be used to control whether simulations are run in
#'   parallel on a default cluster or sequentially in the main process; if a
#'   cluster/value has not been specified by [setup_cluster()], `cores` will
#'   then be set to the value stored in the global `"mc.cores"` option (if
#'   previously set by `options(mc.cores = <number of cores>`), and `1` if that
#'   option has not been specified.\cr
#'   If the resulting number of `cores = 1`, computations will be run
#'   sequentially in the primary process, and if `cores > 1`, a new parallel
#'   cluster will be setup using the `parallel` library and removed once the
#'   function completes. See [setup_cluster()] for details.
#' @param base_seed single integer or `NULL` (default); a random seed used as
#'   the basis for simulations. Regardless of whether simulations are run
#'   sequentially or in parallel, random number streams will be identical and
#'   appropriate (see [setup_cluster()] for details).
#' @param sparse single logical, as described in [run_trial()]; defaults to
#'   `TRUE` when running multiple simulations, in which case only the data
#'   necessary to summarise all simulations are saved for each simulation.
#'   If `FALSE`, more detailed data for each simulation is saved, allowing more
#'   detailed printing of individual trial results and plotting using
#'   [plot_history()] ([plot_status()] does not require non-sparse results).
#' @param progress single numeric `> 0` and `<= 1` or `NULL`. If `NULL`
#'   (default), no progress is printed to the console. Otherwise, progress
#'   messages are printed to the control at intervals proportional to the value
#'   specified by progress.\cr
#'   **Note:** as printing is not possible from within clusters on multiple
#'   cores, the function conducts batches of simulations on multiple cores (if
#'   specified), with intermittent printing of statuses. Thus, all cores have to
#'   finish running their current assigned batches before the other cores may
#'   proceed with the next batch. If there are substantial differences in the
#'   simulation speeds across cores, using `progress` may thus increase total
#'   run time (especially with small values).
#' @param version passed to [saveRDS()] when saving simulations, defaults to
#'   `NULL` (as in [saveRDS()]), which means that the current default version is
#'   used. Ignored if simulations are not saved.
#' @param compress passed to [saveRDS()] when saving simulations, defaults to
#'   `TRUE` (as in [saveRDS()]), see [saveRDS()] for other options. Ignored if
#'   simulations are not saved.
#' @param export character vector of names of objects to export to each
#'   parallel core when running in parallel; passed as the `varlist` argument to
#'   [parallel::clusterExport()]. Defaults to `NULL` (no objects exported),
#'   ignored if `cores == 1`. See **Details** below.
#' @param export_envir `environment` where to look for the objects defined
#'   in `export` when running in parallel and `export` is not `NULL`. Defaults
#'   to the environment from where [run_trials()] is called.
#'
#' @details
#'
#' \strong{Exporting objects when using multiple cores}
#'
#' If [setup_trial()] is used to define a trial specification with custom
#' functions (in the `fun_y_gen`, `fun_draws`, and `fun_raw_est` arguments of
#' [setup_trial()]) and [run_trials()] is run with `cores > 1`, it is necessary
#' to export additional functions or objects used by these functions and defined
#' by the user outside the function definitions provided. Similarly, functions
#' from external packages loaded using [library()] or [require()] must be
#' exported or called prefixed with the namespace, i.e., `package::function`.
#' The `export` and `export_envir` arguments are used to export objects calling
#' the [parallel::clusterExport()]-function. See also [setup_cluster()], which
#' may be used to setup a cluster and export required objects only once per
#' session.
#'
#' @return A list of a special class `"trial_results"`, which contains the
#'   `trial_results` (results from all simulations; note that `seed` will be
#'   `NULL` in the individual simulations), `trial_spec` (the trial
#'   specification), `n_rep`, `base_seed`, `elapsed_time` (the total simulation
#'   run time), `sparse` (as described above) and `adaptr_version` (the version
#'   of the `adaptr` package used to run the simulations). These results may be
#'   extracted, summarised, and plotted using the [extract_results()],
#'   [check_performance()], [summary()], [print.trial_results()],
#'   [plot_convergence()], [check_remaining_arms()], [plot_status()], and
#'   [plot_history()] functions. See these functions' definitions for additional
#'   details and details on additional arguments used to select arms in
#'   simulations not ending in superiority and other summary choices.
#'
#' @export
#'
#' @import parallel
#'
#' @examples
#' # Setup a trial specification
#' binom_trial <- setup_trial_binom(arms = c("A", "B", "C", "D"),
#'                                  true_ys = c(0.20, 0.18, 0.22, 0.24),
#'                                  data_looks = 1:20 * 100)
#'
#' # Run 10 simulations with a specified random base seed
#' res <- run_trials(binom_trial, n_rep = 10, base_seed = 12345)
#'
#' # See ?extract_results, ?check_performance, ?summary and ?print for details
#' # on extracting resutls, summarising and printing
#'
run_trials <- function(trial_spec, n_rep, path = NULL, overwrite = FALSE,
                       grow = FALSE, cores = NULL,
                       base_seed = NULL, sparse = TRUE, progress = NULL,
                       version = NULL, compress = TRUE,
                       export = NULL, export_envir = parent.frame()) {

  # Log starting time and validate inputs
  tic <- Sys.time()
  if (is.null(sparse) | length(sparse) != 1 | any(is.na(sparse)) | !is.logical(sparse)) {
    stop0("sparse must be a single TRUE or FALSE.")
  }
  if ((is.null(path) | overwrite) & !inherits(trial_spec, "trial_spec")) {
    stop0("If a path to a file is not provided or if overwrite = TRUE, ",
          "a valid trial specification must be provided.")
  }
  if (!verify_int(n_rep, min_value = 1)) {
    stop0("n_rep must be a single whole number > 0.")
  }
  if (!(verify_int(cores, min_value = 1) | is.null(cores))) {
    stop0("cores must be NULL or a single whole number > 0.")
  }
  if (grow & overwrite) {
    stop0("Both grow and overwrite are TRUE. At least one of them must be ",
          "FALSE; if grow = TRUE, the object is automatically overwritten.")
  }
  if (ifelse(!is.null(path), file.exists(path), FALSE) & !overwrite) {
    # File exists and overwrite is FALSE
    prev <- readRDS(path)
    # To avoid complicated errors with previous functions related to byte-compiling
    # and environments and not easily solved by using identical(), create two
    # copies of the trial specs and set the function arguments to NULL
    # These are then compared using all.equal, followed by comparison of the
    # deparsed functions (= only the function definitions)
    prev_spec_nofun <- prev$trial_spec
    spec_nofun <- trial_spec
    prev_spec_nofun$fun_y_gen <- prev_spec_nofun$fun_draws <- prev_spec_nofun$fun_raw_est <-
      spec_nofun$fun_y_gen <- spec_nofun$fun_draws <- spec_nofun$fun_raw_est <- NULL
    if (!isTRUE(all.equal(prev_spec_nofun, spec_nofun)) |
        !equivalent_funs(prev$trial_spec$fun_y_gen, trial_spec$fun_y_gen) |
        !equivalent_funs(prev$trial_spec$fun_draws, trial_spec$fun_draws) |
        !equivalent_funs(prev$trial_spec$fun_raw_est, trial_spec$fun_raw_est)) {
      stop0("The trial specification contained in the object in path is not ",
            "the same as the one provided; thus the previous result was not loaded.")
    } else {
      prev_adaptr_version <- prev$adaptr_version
      if ((is.null(prev_adaptr_version) | isTRUE(prev_adaptr_version < .adaptr_version))) {
        stop0("The object in path was created by a previous version of adaptr and ",
              "cannot be used by this version of adaptr unless the object is updated. ",
              "Type 'help(\"update_saved_trials\")' for help on updating.")
      }
    }
    prev_n_rep <- prev$n_rep
    if (prev_n_rep != n_rep) {
      if (!grow | n_rep <= prev_n_rep) {
        stop0(paste0("n_rep is provided in the call and in the loaded object, ",
                     "but they are not the same (n_rep = ", n_rep, ", previous ",
                     "n_rep = ", prev_n_rep, ").\n",
                     "This is only permitted if the provided n_rep is larger ",
                     "than the n_rep in the loaded object and grow = TRUE."))
      }
    } else if (grow & prev_n_rep == n_rep) {
      warning0(paste0("grow = TRUE, but the provided n_rep is equal to the ",
                      "n_rep in the loaded object (both = ", n_rep, ").\n",
                      "When grow = TRUE, the provided n_rep must be larger ",
                      "than the n_rep in the loaded object.\n",
                      "Ignoring grow and returning previous object."))
      grow <- FALSE
    }
    prev_base_seed <- prev$base_seed
    if (!is.null(prev_base_seed) & !is.null(base_seed)) {
      if (prev_base_seed != base_seed) {
        stop0(paste0("A base_seed is provided in the call and in the loaded ",
                     "object, but they are not the same (base_seed = ",
                     base_seed, ", previous base_seed = ", prev_base_seed, ")."))
      }
    }
    if (prev$sparse != sparse) {
      stop0(paste0("Identical values must be provided for the sparse argument ",
                   "in the call and the previous object (sparse = ", sparse,
                   ", previous sparse = ", prev$sparse, ")."))
    }
  } else if (grow) {
    stop0("grow = TRUE, but a previous object does not exist.")
  }
  if (!is.null(base_seed)) {
    if (!verify_int(base_seed)) {
      stop0("base_seed must be either NULL or a single whole number.")
    }
  }
  if (!is.null(progress)) {
    if (!isTRUE(length(progress) == 1 & is.numeric(progress) & !(is.na(progress)) && progress >= 0.01 && progress <= 1)) {
      stop0("progress must be either NULL or a single numeric value >= 0.01 and <= 1.")
    }
  }

  # Run simulations, load object and run additional trials, or just load object
  action <- 3 # 1 = new, 2 = grow, 3 = previous
  if (is.null(path) | overwrite | ifelse(!is.null(path), !file.exists(path), FALSE)) { # Run trials - no growing
    action <- 1
    prev_n_rep <- 0 # Start from the beginning
    prev_res <- NULL # Don't reuse
    elapsed_time <- 0
  } else if (grow) {
    action <- 2
    prev_res <- prev$trial_results
    elapsed_time <- prev$elapsed_time
  }

  if (action < 3) { # Grow or new
    n_rep_new <- n_rep - prev_n_rep

    # Create random seeds
    if (!is.null(base_seed)) {
      if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) { # A global random seed exists (not the case when called from parallel::parLapply)
        oldseed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
        on.exit(assign(".Random.seed", value = oldseed, envir = globalenv(), inherits = FALSE), add = TRUE, after = FALSE)
      }
      old_rngkind <- RNGkind("L'Ecuyer-CMRG", "default", "default")
      on.exit(RNGkind(kind = old_rngkind[1], normal.kind = old_rngkind[2], sample.kind = old_rngkind[3]), add = TRUE, after = FALSE)
      set.seed(base_seed)
      seeds <- list(get(".Random.seed", envir = globalenv(), inherits = FALSE))
      if (n_rep > 1) {
        for (i in 2:n_rep) {
          seeds[[i]] <- nextRNGStream(seeds[[i - 1]])
        }
      }
    } else {
      seeds <- rep(list(NULL), n_rep)
    }

    # If cores is NULL, use defaults
    if (is.null(cores)) {
      cl <- .adaptr_cluster_env$cl # Load default cluster if existing
      # If cores is not specified by setup_cluster(), use global option or 1
      cores <- .adaptr_cluster_env$cores %||% getOption("mc.cores", 1)
    } else { # cores specified, ignore defaults
      cl <- NULL
    }

    # If parallel, export and setup new cluster if needed
    if (cores > 1) {
      if (is.null(cl)) { # Set up new, temporary cluster
        cl <- makePSOCKcluster(cores)
        on.exit(stopCluster(cl), add = TRUE, after = FALSE)
        clusterEvalQ(cl, RNGkind("L'Ecuyer-CMRG", "default", "default"))
      }
      if (!is.null(export)) clusterExport(cl = cl, varlist = export, envir = export_envir)
    }

    # Run simulations
    if (is.null(progress)) { # No progress printed
      trials <- dispatch_trial_runs(is = (prev_n_rep + 1):n_rep, trial_spec = trial_spec,
                                    seeds = seeds, sparse = sparse, cores = cores,
                                    cl = if (cores > 1) cl else NULL)
    } else { # Print progress
      # Prepare
      prog_vals <- prog_breaks(progress = progress, prev_n_rep = prev_n_rep, n_rep_new = n_rep_new, cores = cores)
      trials <- list()
      prog_prev_n <- 0
      if (prev_n_rep > 0) cat0("run_trials: loaded ", prev_n_rep, " previous simulations, running ", n_rep_new, " new\n")
      cat0(prog_vals$start_mess, "\n")
      # Loop
      for (i in seq_along(prog_vals$breaks)) {
        # Run simulations
        trials[[i]] <- dispatch_trial_runs(is = prog_vals$batches[[i]], trial_spec = trial_spec,
                                           seeds = seeds, sparse = sparse, cores = cores,
                                           cl = if (cores > 1) cl else NULL)
        # Print status including timestamp
        tmdf <- Sys.time() - tic
        cat0(prog_vals$prog_mess[i], " [", fmt_dig(as.numeric(tmdf), dig = 2), " ", attr(tmdf, "units"), "]", "\n")
      }
      cat("\n")
      # Bind results
      trials <- do.call(c, trials)
    }

    # Prepare result
    res <- structure(list(trial_results = c(prev_res, trials),
                          trial_spec = trial_spec,
                          n_rep = n_rep,
                          base_seed = base_seed,
                          elapsed_time = elapsed_time + Sys.time() - tic,
                          sparse = sparse, adaptr_version = .adaptr_version),
                     class = c("trial_results", "list"))

    if (ifelse(!is.null(path), !file.exists(path) | overwrite | grow, FALSE)) {
      saveRDS(res, file = path, version = version, compress = compress)
    }
  } else { # Don't run new simulations - return previous object
    res <- prev
  }

  # Return
  res
}
