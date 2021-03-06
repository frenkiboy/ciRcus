# ---------------------------------------------------------------------------- #
#' Build and save a TxDb object containing gene annotation
#'
#' Loads the GTF file for the selected assembly, drops non-standard chromosomes,
#' adds "chr" prefix to Ensembl chromosome names and saves the SQLite database
#' to \code{db.file}
#'
#'
#' @param assembly abbreviation for one of the supported assemblies
#' @param db.file a file to save SQLite database to
#'
#' @export
#' @importFrom AnnotationDbi saveDb
gtf2sqlite <- function(assembly = c("hg19", "hg38", "mm10", "rn5", "dm6"), db.file) {

  ah <- AnnotationHub()
  gtf.gr <- ah[[getOption("assembly2annhub")[[assembly]]]]
  gtf.gr <- keepStandardChromosomes(gtf.gr)
  seqlevels(gtf.gr) <- paste("chr", seqlevels(gtf.gr), sep="")
  seqlevels(gtf.gr)[which(seqlevels(gtf.gr) == "chrMT")] <- "chrM"
  txdb <- makeTxDbFromGRanges(gtf.gr, drop.stop.codons = FALSE, metadata = data.frame(name="Genome", value="GRCh37"))
  saveDb(txdb, file=db.file)

}


# ---------------------------------------------------------------------------- #
#' Load annotation and prepare a list of features for later
#'
#' Loads a local .sqlite TxDb annotation file (e.g. created using \code{gtf2sqlite}),
#' returns a list of features needed for circRNA annotation.
#'
#' @param txdb.file path to the TxDb gene annotation file saved as SQLite database
#'
#' @export
#' @importFrom AnnotationDbi loadDb
loadAnnotation <- function(txdb.file) {

  txdb <- loadDb(txdb.file)
  exns <- unique(exons(txdb))
  junct.start <- exns
  end(junct.start) <- start(junct.start)
  junct.end <- exns
  start(junct.end) <- end(junct.end)

  gene.feats <- GRangesList(utr5   = reduce(unlist(fiveUTRsByTranscript(txdb))),
                            utr3   = reduce(unlist(threeUTRsByTranscript(txdb))),
                            cds    = reduce(cds(txdb)),
                            intron = reduce(unlist(intronsByTranscript(txdb))))
  junctions <- GRangesList(start = junct.start,
                           end   = junct.end)

  genes <- genes(txdb)

  return(list(genes = genes, gene.feats = gene.feats, junctions = junctions))
}

# ---------------------------------------------------------------------------- #
#' Load and annotate a list of circRNA candidates
#'
#' Loads a list of splice junctions detected using \code{find_circ.py}
#' (Memczak et al. 2013; www.circbase.org), applies quality filters,
#' calculates circular-to-linear ratios, and extends the input with
#' genomic features
#'
#' @param circs.bed a list of splice junctions (linear and circular), generated using \code{find_circ.py}.
#' @param annot.list list of relevant genomic features generated using \code{loadAnnotation()}
#' @param assembly what genome assembly the input data are coming from
#'
#' @export
annotateCircs <- function(circs.bed, annot.list, assembly = c("hg19", "hg38", "mm10", "rn5", "dm6")) {

  DT <- readCircs(file = circs.bed)
  DT <- circLinRatio(sites = DT)
  #DT <- getIDs(DT, "hsa", "hg19")
  DT$start <- DT$start + 1
  DT <- annotateHostGenes(circs = DT, genes.gr = annot.list$genes)
  DT <- annotateFlanks(circs = DT, annot.list = annot.list$gene.feats)
  DT <- annotateJunctions(circs = DT, annot.list = annot.list$junctions)
  DT$gene <- ensg2name(ensg = DT$host, organism = getOption("assembly2organism")[[assembly]], release = getOption("assembly2release")[[assembly]])

  return(DT)
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#' details
#'
#' @param circs
#'
annotateHostGenes <- function(circs, genes.gr) {

  # circs to GR
  circs.gr <- GRanges(seqnames=circs$chrom,
                      ranges=IRanges(start=circs$start,
                                     end=circs$end),
                      strand=circs$strand,
                      id=paste(circs$chrom, ":", circs$start, "-", circs$end, sep=""))
  circs.gr <- sort(circs.gr)


  # GR with circ starts and ends only (left and right flanks, actually)
  circ.starts.gr <- circs.gr
  end(circ.starts.gr) <- start(circ.starts.gr)
  circ.ends.gr <- circs.gr
  start(circ.ends.gr) <- end(circ.ends.gr)

  olap.start <- findOverlaps(circ.starts.gr, genes.gr, type="within")
  olap.end   <- findOverlaps(circ.ends.gr, genes.gr, type="within")

  circs$id <- paste(circs$chrom, ":", circs$start, "-", circs$end, sep="")
  circs$start.hit <- circs$id %in% circs.gr$id[queryHits(olap.start)]
  circs$end.hit   <- circs$id %in% circs.gr$id[queryHits(olap.end)]

  matches.start <- data.table(id=circs.gr$id[queryHits(olap.start)], gene=names(genes.gr)[subjectHits(olap.start)] )
  matches.end   <- data.table(id=circs.gr$id[queryHits(olap.end)],   gene=names(genes.gr)[subjectHits(olap.end)] )

  start.list <- lapply(split(matches.start, matches.start$id), function(x) x$gene)
  end.list   <- lapply(split(matches.end,   matches.end$id),   function(x) x$gene)

  circs <- merge(circs, data.table(id=names(start.list), starts=sapply(start.list, function(x) paste(x, collapse=","))), by="id", all.x=T)
  circs <- merge(circs, data.table(id=names(end.list), ends=sapply(end.list, function(x) paste(x, collapse=","))), by="id", all.x=T)

  hs <- hash(start.list)
  he <- hash(end.list)

  circs$hit.ctrl <- circs$id %in% unique(c(keys(hs), keys(he)))

  #ptm <- proc.time()
  tmphits <- integer()
  tmpgenes <- integer()
  host.candidates <- integer()
  for (circ in circs$id) {
    tmphits <- append(tmphits, sum(hs[[circ]] %in% he[[circ]]))
    tmpgenes <- append(tmpgenes, paste(hs[[circ]][hs[[circ]] %in% he[[circ]]], collapse=","))
    host.candidates <- append(host.candidates, length(unique(c(hs[[circ]], he[[circ]]))))
  }
  #proc.time() - ptm
  circs$hitcnt <- tmphits
  circs$hitgenes <- tmpgenes
  circs$host.candidates <- host.candidates

  circs$host[circs$hitcnt == 1] <- circs$hitgenes[circs$hitcnt == 1]
  circs$host[circs$hitcnt > 1]  <- "ambiguous"
  circs$host[circs$hitcnt == 0 & circs$start.hit == FALSE & circs$end.hit == FALSE] <- "intergenic" # TODO: actually, some of them may have a putative host gene within, I was only testing starts/ends
  circs$host[circs$hitcnt == 0 & circs$start.hit == TRUE  & circs$end.hit == TRUE]  <- "no_single_host"
  circs$host[circs$hitcnt == 0 & xor(circs$start.hit, circs$end.hit) & circs$host.candidates > 1] <- "ambiguous"
  circs$host[circs$hitcnt == 0 & circs$start.hit == TRUE  & circs$end.hit == FALSE & circs$host.candidates == 1] <- circs$starts[circs$hitcnt == 0 & circs$start.hit == TRUE   & circs$end.hit == FALSE & circs$host.candidates == 1]
  circs$host[circs$hitcnt == 0 & circs$start.hit == FALSE & circs$end.hit == TRUE & circs$host.candidates == 1]  <- circs$ends[circs$hitcnt == 0   & circs$start.hit == FALSE  & circs$end.hit == TRUE  & circs$host.candidates == 1]

  #return(circs)
  return(circs[, !c("id", "start.hit", "end.hit", "starts", "ends", "hit.ctrl", "hitcnt", "hitgenes", "host.candidates"), with=F])
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#'
#' details
#'
#' @param circs
#'
annotateFlanks <- function(circs, annot.list) {

  # cat('Munging input data...\n')
  circs.gr <- GRanges(seqnames=circs$chrom,
                      ranges=IRanges(start=circs$start,
                                     end=circs$end),
                      strand=circs$strand,
                      id=paste(circs$chrom, ":", circs$start, "-", circs$end, sep=""))
  circs.gr <- sort(circs.gr)

  # GR with circ starts and ends only (left and right flanks, actually)
  circ.starts.gr <- circs.gr
  end(circ.starts.gr) <- start(circ.starts.gr)
  circ.ends.gr <- circs.gr
  start(circ.ends.gr) <- end(circ.ends.gr)

  # cat('Annotating circRNAs...\n')
  circ.starts.gr$feat_start     <- AnnotateRanges(r1 = circ.starts.gr, l = annot.list,  null.fact = "intergenic", type="precedence")
  # circ.starts.gr$feat_start_all <- AnnotateRanges(r1 = circ.starts.gr, l = annot.list, type="all")
  circ.ends.gr$feat_end         <- AnnotateRanges(r1 = circ.ends.gr,   l = annot.list,  null.fact = "intergenic", type="precedence")
  # circ.ends.gr$feat_end_all     <- AnnotateRanges(r1 = circ.ends.gr,   l = annot.list, type="all")

  # cat('Merging data')
  circs$id <- paste(circs$chrom, ":", circs$start, "-", circs$end, sep="")
  circs <- merge(circs, data.table(as.data.frame(GenomicRanges::values(circ.starts.gr))), by="id")
  circs <- merge(circs, data.table(as.data.frame(GenomicRanges::values(circ.ends.gr))), by="id")
  circs[, feature:=character(.N)]
  circs$feature[circs$feat_start == circs$feat_end] <- circs$feat_start[circs$feat_start == circs$feat_end]
  circs$feature[circs$feature == "" & circs$strand == "+"] <- paste(circs$feat_start[circs$feature == "" & circs$strand == "+"], circs$feat_end[circs$feature == "" & circs$strand == "+"], sep=":")
  circs$feature[circs$feature == "" & circs$strand == "-"] <- paste(circs$feat_end[circs$feature == "" & circs$strand == "-"],   circs$feat_start[circs$feature == "" & circs$strand == "-"], sep=":")

  return(circs[, !c("id", "feat_start", "feat_end"), with = F])
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#'
#' details
#'
#' @param circs
#'
annotateJunctions <- function(circs, annot.list) {

  # cat('Munging input data...\n')
  circs.gr <- GRanges(seqnames=circs$chrom,
                      ranges=IRanges(start=circs$start,
                                     end=circs$end),
                      strand=circs$strand,
                      id=paste(circs$chrom, ":", circs$start, "-", circs$end, sep=""))
  circs.gr <- sort(circs.gr)

  # GR with circ starts and ends only (left and right flanks, actually)
  circ.starts.gr <- circs.gr
  end(circ.starts.gr) <- start(circ.starts.gr)
  circ.ends.gr <- circs.gr
  start(circ.ends.gr) <- end(circ.ends.gr)

  # cat('Annotating circRNAs...\n')
  circ.starts.gr$annotated_start_junction <- AnnotateRanges(r1 = circ.starts.gr, l = annot.list, type="precedence")
  circ.ends.gr$annotated_end_junction <- AnnotateRanges(r1 = circ.ends.gr,   l = annot.list, type="precedence")

  # cat('Merging data')
  circs$id <- paste(circs$chrom, ":", circs$start, "-", circs$end, sep="")
  circs <- merge(circs, data.table(as.data.frame(GenomicRanges::values(circ.starts.gr))), by="id")
  circs <- merge(circs, data.table(as.data.frame(GenomicRanges::values(circ.ends.gr))), by="id")

  circs$annotated_start_junction[circs$annotated_start_junction != "None"] <- TRUE
  circs$annotated_start_junction[circs$annotated_start_junction == "None"] <- FALSE
  circs$annotated_end_junction[circs$annotated_end_junction != "None"] <- TRUE
  circs$annotated_end_junction[circs$annotated_end_junction == "None"] <- FALSE

  circs$junct.known[circs$annotated_start_junction == TRUE  & circs$annotated_end_junction == TRUE]  <- "both"
  circs$junct.known[circs$annotated_start_junction == FALSE & circs$annotated_end_junction == FALSE] <- "none"
  circs$junct.known[circs$annotated_start_junction == TRUE  & circs$annotated_end_junction == FALSE & circs$strand == "+"] <- "5pr"
  circs$junct.known[circs$annotated_start_junction == TRUE  & circs$annotated_end_junction == FALSE & circs$strand == "-"] <- "3pr"
  circs$junct.known[circs$annotated_start_junction == FALSE & circs$annotated_end_junction == TRUE  & circs$strand == "+"] <- "3pr"
  circs$junct.known[circs$annotated_start_junction == FALSE & circs$annotated_end_junction == TRUE  & circs$strand == "-"] <- "5pr"

  return(circs[, !c("id", "annotated_start_junction", "annotated_end_junction"), with = F])
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#' annotates the ranges with the corresponding list
#'
#' details
#'
#' @param circs
#'
AnnotateRanges = function(r1, l, ignore.strand=FALSE, type = 'precedence', null.fact = 'None', collapse.char=':') {

  if(! class(r1) == 'GRanges')
    stop('Ranges to be annotated need to be GRanges')

  if(! all(sapply(l, class) == 'GRanges'))
    stop('Annotating ranges need to be GRanges')

  if(!type %in% c('precedence','all'))
    stop('type may only be precedence and all')

  # require(data.table)
  # require(GenomicRanges)
  # cat('Overlapping...\n')
  if(class(l) != 'GRangesList')
    l = GRangesList(lapply(l, function(x){values(x)=NULL;x}))
  a = suppressWarnings(data.table(as.matrix(findOverlaps(r1, l, ignore.strand=ignore.strand))))
  a$id = names(l)[a$subjectHits]
  a$precedence = match(a$id,names(l))[a$subjectHits]
  a = a[order(a$precedence)]

  if(type == 'precedence'){
    # cat('precedence...\n')
    a = a[!duplicated(a$queryHits)]
    annot = rep(null.fact, length(r1))
    annot[a$queryHits] = a$id
  }
  if(type == 'all'){
    # cat('all...\n')
    a = a[,list(id=paste(unique(id),collapse=collapse.char)),by='queryHits']
    annot = rep(null.fact, length(r1))
    annot[a$queryHits] = a$id

  }

  return(annot)
}

# ---------------------------------------------------------------------------- #
#' title
#'
#' description
#'
#'
#' details
#'
#' @param ensg character vector of ensembl gene ids
#'
ensg2name <- function(ensg, organism, release = "current") {

  ensembl.host <- getOption("ensembl.release")[[release]]

  ensembl = useMart(biomart = "ENSEMBL_MART_ENSEMBL", host = ensembl.host)
  ensembl = useDataset(dataset = paste(getOption("ensembl.organism")[[organism]], "_gene_ensembl", sep=""), mart = ensembl)

  xrefs <- getBM(attributes = c("external_gene_id", "ensembl_gene_id"),
                 filter     = "ensembl_gene_id",
                 values     = ensg,
                 mart       = ensembl)

  out.dt <- data.table(ensembl_gene_id = ensg)
  out.dt <- merge(out.dt, xrefs, by = "ensembl_gene_id", all.x = T)
  out.dt <- out.dt[match(ensg, out.dt$ensembl_gene_id)]

  return(out.dt$external_gene_id)
}
