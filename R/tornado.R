#' @importFrom rlang .data
NULL

#' Tornado sampling and plotting function
#'
# -------------------------------------------------------------------------
#' A small wrapper around lapply that loops over a functions parameters,
#' sampling one whilst fixing the others. `tornado_sample()` just wraps a
#' simple univariate sensitivity analysis, ensuring the output is formatted in a
#' usable way for the namesake plot function.
#'
# -------------------------------------------------------------------------
#' @returns
#'
#' For `tornado_sample()` a tibble with class **tornado_samples** and an
#' additional attribute that gives the baseline value calculated when setting
#' each argument to it's distributions mean value (or an optional,
#' user-supplied, value). For `tornado_plot()`, a `ggplot2` object
#'
# -------------------------------------------------------------------------
#' @name tornado
NULL

# -------------------------------------------------------------------------
#' @param n Number of samples.
#'
#' @param fun A vectorised function.
#'
#' @param distributions Distributions created with the
#' [distributions3](https://alexpghayes.github.io/distributions3/) package that
#' correspond to the named parameters of `fun`.
#'
#' @param baseline NULL or a scalar numeric value. If not NULL then this value
#' is used as the comparitor when producing the latter tornado plots.
#'
#' @param output_name The name to use of the result column in the output
#' tibbles. This must not correspond to any of the parameter names of `fun`.
#'
#' @param ... Not currently used.
#'
# -------------------------------------------------------------------------
#' @examples
#'
#' # User inputs ----------------------------------------------------------
#'
#' # Function with desired arguments
#' # NOTE: MUST be vectorised by the user and return a scalar value
#' fun <- function(cost_per_day, days, discount) cost_per_day * days * discount
#'
#' # A distribution (from distributions3) for each function argument
#' distributions <- list(
#'     cost_per_day = distributions3::Gamma(shape = 9, rate = 0.5),
#'     days         = distributions3::Gamma(shape = 5, rate = 1),
#'     discount     = distributions3::Beta(alpha = 2, beta = 40)
#' )
#'
#' # Number of samples to take for each argument
#' samples <- 1000
#'
#' # Package functionality ------------------------------------------------
#'
#' # generate the samples for each parameter
#' dat <- tornado_sample(samples, fun, distributions)
#'
#' # jitter plot
#' tornado_plot(dat)
#'
#' # plot of the extremes (akin to the more traditional plots)
#' tornado_plot(dat, type = "maxmin")
#'
# -------------------------------------------------------------------------
#' @rdname tornado
#' @export
tornado_sample <- function(n, fun, distributions, ..., baseline = NULL, output_name = ".result") {

    rlang::check_dots_empty0(...)
    stopifnot(
        is.function(fun),
        is.numeric(n) && length(n) == 1L && !is.na(n) && n %% 1 == 0,
        is.list(distributions),
        all(vapply(distributions, distributions3::is_distribution, TRUE)),
        is.character(output_name) && length(output_name) == 1L && !is.na(output_name)
    )
    funargs <- methods::formalArgs(fun)
    funargs <- funargs[funargs != "..."]
    distnms <- names(distributions)
    stopifnot(setequal(funargs, distnms) && length(distnms) == length(funargs))
    if (output_name %in% distnms) {
        stop("`output_name` (%s) must be different to the parameter names of `fun`. ", output_name)
    }

    # calculate the distribution means
    means <- lapply(distributions, mean)

    # calculate the baseline output
    if (is.null(baseline)) {
        baseline <- do.call(fun, means)
    }
    stopifnot(is.numeric(baseline) && length(baseline) == 1L && !is.na(baseline))

    # calculate the sample outputs
    sample_outputs <- lapply(seq_along(distributions), function(i) {
        inputs <- means
        varying <- list(.varying = distnms[[i]])
        X <- distributions[[i]]
        random_inputs <- distributions3::random(X, n)
        col <- ifelse (random_inputs < means[[i]], "less", "more")
        inputs[[i]] <- random_inputs
        results <- do.call(fun, inputs)
        if (length(results) != length(random_inputs)) {
            stop("Incompatible outputs. Your function must be vectorised returning length n outputs for length n inputs.")
        }
        out <- c(inputs, list(do.call(fun, inputs)))
        names(out)[length(out)] <- output_name
        out <- tibble::as_tibble(out)
        attr(out, "col") <- col
        out
    })
    names(sample_outputs) <- distnms

    structure(
        sample_outputs,
        baseline = baseline,
        output_name = output_name,
        class = "tornado_samples"
    )
}

# -------------------------------------------------------------------------
#' @param x Output from `tornado_sample()`.
#'
#' @param type Character string. Either 'jitter' or 'maxmin'. If 'jitter' then
#' we simply plot the sample results against the corresponding distribution that
#' varies. Otherwise, we plot the corresponding maximum and minimum values as a
#' split bar chart.
#'
#' @param nbreaks Passed to `scales::breaks_extended()`.
#'
#' @param xlab The label for the x-axis.
#'
# -------------------------------------------------------------------------
#' @rdname tornado
#'
# -------------------------------------------------------------------------
#' @export
tornado_plot <- function(x, ..., type = c("jitter", "maxmin"), nbreaks = 6, xlab = "value") {

    rlang::check_dots_empty0(...)
    stopifnot(
        inherits(x, "tornado_samples"),
        is.numeric(nbreaks) && length(nbreaks) == 1L && !is.na(nbreaks) && nbreaks %% 1 == 0,
        is.character(xlab) && length(xlab) == 1L && !is.na(xlab)
    )
    type <- match.arg(type)

    dat <- do.call(rbind, x)
    baseline <- attr(x, "baseline")
    negative <- dat$.result < baseline
    names <- rep(names(x), times = vapply(x, nrow, 1L))
    cols <- unlist(lapply(x, attr, "col"), use.names = FALSE)
    result_column <- attr(x, "output_name")
    result <- dat[[result_column]]

    # calculate rough plot limits
    spread <- max(result) - min(result)
    lower <- min(result) - spread / 10
    upper <- max(result) + spread / 10

    dat <- data.frame(value = dat$.result, varying = names, colour = cols)
    # calculate the order
    ord <- aggregate(value ~ varying, data = dat, FUN = \(x) max(x) - min(x))
    ord <- ord$varying[order(ord$value)]
    dat$varying <- factor(dat$varying, levels = ord)

    if (type == "jitter") {
        breaks <- scales::breaks_extended(n = nbreaks)(c(lower, upper))
        ggplot2::ggplot(dat, ggplot2::aes(.data$value, .data$varying, col = .data$colour)) +
            ggplot2::geom_jitter() +
            ggplot2::theme_minimal() +
            ggplot2::theme(
                axis.title.y = ggplot2::element_blank(),
                legend.position = "none"
            ) +
            ggplot2::xlab(xlab) +
            ggplot2::geom_vline(xintercept = baseline, linetype = "dashed") +
            ggplot2::coord_cartesian(xlim = c(lower, upper)) +
            ggplot2::scale_x_continuous(breaks = breaks, labels = breaks) +
            ggplot2::scale_colour_manual(values = c("lightskyblue", "indianred"))
    } else {

        dat$plot_value <- dat$value - baseline
        dat <- stats::aggregate(
            plot_value ~ varying + colour,
            data = dat,
            FUN = function(x) if (x[1L] < 0) min(x) else (max(x))
        )
        breaks <- scales::breaks_extended(n = nbreaks)(c(lower, upper)) - baseline
        labels <- breaks + baseline
        ggplot2::ggplot(dat, ggplot2::aes(.data$plot_value, .data$varying, fill = .data$colour)) +
            ggplot2::geom_col() +
            ggplot2::theme_minimal() +
            ggplot2::theme(
                axis.title.y = ggplot2::element_blank(),
                legend.position = "none"
            ) +
            ggplot2::xlab(xlab) +
            ggplot2::geom_vline(xintercept = 0, linetype = "dashed") +
            ggplot2::coord_cartesian(xlim = c(lower, upper) - baseline) +
            ggplot2::scale_x_continuous(
                breaks = breaks,
                labels = labels
            ) +
            ggplot2::scale_fill_manual(values = c("lightskyblue", "indianred"))

    }
}
