# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#' details
#'
#' @param chrom
#' @param start
#' @param end
#'
#'
getIDs <- function(circs, organism, assembly, chrom="chrom", start="start", end="end", strand="strand") {

  con <- dbConnect(drv    = dbDriver("MySQL"),
                   host   = getOption("circbase.host"),
                   user   = getOption("circbase.user"),
                   pass   = getOption("circbase.pass"),
                   dbname = getOption("circbase.db"))

  query <- paste( "SELECT circID, chrom, pos_start, pos_end, strand FROM ",
                  organism, "_", assembly, "_circles", sep="")

  rs <- dbSendQuery(con, query)
  chunk <- data.table(fetch(rs, n=-1))
  chunk$id <- paste(chunk$chrom, ":", chunk$pos_start, "-", chunk$pos_end, sep="")

  circs$id <- paste(circs[[chrom]], ":", circs[[start]], "-", circs[[end]], sep="")
  out <- merge(circs, chunk[,.(id, circID)], by="id", all.x=T)

  dbHasCompleted(rs)
  dbClearResult(rs)
  dbListTables(con)
  dbDisconnect(con)

  return(out[, !"id", with=F])
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#' details
#'
#' @param chrom
#' @param start
#' @param end
#'
getStudiesList <- function(organism = NA, assembly = NA, study = NA, sample = NA) {

  con <- dbConnect(drv    = dbDriver("MySQL"),
                   host   = getOption("circbase.host"),
                   user   = getOption("circbase.user"),
                   pass   = getOption("circbase.pass"),
                   dbname = getOption("circbase.db"))

  if (is.na(organism) & is.na(assembly) & is.na(study) & is.na(sample)) {
    tbls <- dbListTables(con)
    tbls <- tbls[grep("stats", tbls)]
    #select distinct expID, sample from hsa_hg19_circID_stats order by expID, sample;
  }

  out <- data.table(orgn = factor(), asm = factor(), stdy = factor(), smpl = factor())
  for (tbl in tbls) {
    ORGN <- strsplit(tbl, "_")[[1]][1]
    ASM  <- strsplit(tbl, "_")[[1]][2]

    query <- paste("SELECT DISTINCT expID, sample FROM ", tbl, " order by expID, sample", sep="")
    rs <- dbSendQuery(con, query)
    chunk <- data.table(fetch(rs, n=-1))
    setnames(chunk, c("stdy", "smpl"))
    out <- rbind(out, cbind(orgn=ORGN, asm=ASM, chunk))

  }

  dbHasCompleted(rs)
  dbClearResult(rs)
  dbListTables(con)
  dbDisconnect(con)

  if (!is.na(organism)) {
    out <- out[orgn %in% organism]
  }
  if (!is.na(assembly)) {
    out <- out[asm %in% assembly]
  }
  if (!is.na(study)) {
    out <- out[stdy %in% study]
  }
  if (!is.na(sample)) {
    out <- out[smpl %in% sample]
  }

  setnames(out, c("organism", "assembly", "study", "sample"))

  if (nrow(out) == 0) {
    stop(paste("no circBase data for organism ", organism, ", assembly ", assembly, ", study ", study, ", and sample ", sample, ".", sep=""))
  }

  return(out)
}
