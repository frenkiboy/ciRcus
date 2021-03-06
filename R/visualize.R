# ---------------------------------------------------------------------------- #
#' Plot a histogram of circRNA read counts
#'
#' Histogram shows the read count distribution of input circRNAs.
#'
#' @param circs a list of circRNA candidates, loaded and annotated using \code{annotateCircs()}
#' @param binwidth argument for histogram
#' @return ggplot2 histogram
#'
#' @export
circHist <- function(circs, binwidth = 0.7) {

  p <- ggplot(circs, aes(x = n_reads)) +
        geom_histogram(binwidth = binwidth) +
        coord_trans(y = "sqrt") +
        scale_x_sqrt(breaks = c(1, 10, 50, 100, 250, 500, 750)) +
        scale_y_continuous(breaks = c(0, 1, 10, 50, 100, 250, 500, 750, 1000, 2000, 3000)) +
        #scale_y_continuous(breaks=c(0, 10, 50, 100, 250, 500, 750, 1000, 2000, 3000, 4000, 5000)) +
        xlab("#reads on head-to-tail splice junction") +
        ylab("#circRNAs") +
        theme(axis.title.y = element_text(size=20),
              axis.title.x = element_text(size=20),
              axis.text.x = element_text(size=16),
              axis.text.y = element_text(size=16))

  return(p)

}

# ---------------------------------------------------------------------------- #
#' A piechart of gene features input circRNAs are spliced from
#'
#' Describes proportions of circRNAs coming from particular gene features
#' (coding sequence, UTRs, introns, intergenic regions, ...). Low-frequency
#' features can be collapsed to "other".
#'
#' @param circs a list of circRNA candidates, loaded and annotated using \code{annotateCircs()}
#' @param other.threshold a minimum number of candidates feature should
#'                        have to be present in the pie-chart. Can be expressed
#'                        as fraction, or raw number.
#' @return ggplot2 pie-chart
#'
#' @export
#' @importFrom RColorBrewer brewer.pal
annotPie <- function(circs, other.threshold) {

  if (hasArg(other.threshold)) {

    if (other.threshold < 1) {

      thresh <- round(other.threshold*nrow(circs))

    } else {

      thresh <- other.threshold

    }

  } else {

    thresh <- 0

  }

  collapse.to.other <- names(table(circs$feature)[table(circs$feature) < thresh])

  tbl <- table(circs$feature)
  # tbl <- tbl[order(tbl, decreasing=T)]
  tmpdf <- data.table(feature = rep(names(tbl), tbl))
  tmpdf$feature[tmpdf$feature %in% collapse.to.other] <- "other"

  nms <- names(table(tmpdf$feature))[order(table(tmpdf$feature), decreasing = T)]
  if ("other" %in% nms) nms <- c(nms[nms != "other"], "other")

  tmpdf$feature <- factor(tmpdf$feature, levels = nms)

  pie <- ggplot(tmpdf, aes(x = factor(1), fill = factor(feature))) +
          geom_bar(width = 1) +
          xlab("") +
          ylab("") +
          theme(	axis.line=element_blank(),
                 axis.text.x=element_blank(),
                 axis.text.y=element_blank(),
                 axis.ticks=element_blank(),
                 axis.title.x=element_blank(),
                 axis.title.y=element_blank(),
                 panel.background=element_blank(),panel.border=element_blank(),panel.grid.major=element_blank(),
                 panel.grid.minor=element_blank(),plot.background=element_blank(),
                 legend.title=element_blank()) +
          coord_polar(theta = "y")

  if (nlevels(tmpdf$feature) <= 9) {
    pie <- pie + scale_fill_manual(values = rev(brewer.pal(name="Blues", n=nlevels(tmpdf$feature))))
  }

  return(pie)
}
