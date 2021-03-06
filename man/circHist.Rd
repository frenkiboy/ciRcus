% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/visualize.R
\name{circHist}
\alias{circHist}
\title{Plot a histogram of circRNA read counts}
\usage{
circHist(circs, binwidth = 0.7)
}
\arguments{
\item{circs}{a list of circRNA candidates, loaded and annotated using \code{annotateCircs()}}

\item{binwidth}{argument for histogram}
}
\value{
ggplot2 histogram
}
\description{
Histogram shows the read count distribution of input circRNAs.
}

