#internal function for spatial mapping
ShiftCell <- function(bin, x, y) {
  bin.y <- (bin - 1) %/% 8 + 1
  bin.x <- (bin - 1) %% 8 + 1
  new.x <- MinMax(data = bin.x + x, min = 1, max = 8)
  new.y <- MinMax(data = bin.y + y, min = 1, max = 8)
  new.bin <- 8 * (new.y - 1) + new.x
  return(new.bin)
}

NeighborCells <- function(bin) {
  return(unique(x = c(
    bin,
    ShiftCell(bin = bin, x = 0, y = 1),
    ShiftCell(bin = bin, x = 1, y = 0),
    ShiftCell(bin = bin, x = -1, y = 0),
    ShiftCell(bin = bin, x = 0, y = -1)
  )))
}

AllNeighborCells <- function(bin, dist = 1) {
  all.comb <- expand.grid(rep(x = list(-dist:dist), 2))
  return(unique(x = unlist(x = lapply(
    X = 1:nrow(x = all.comb),
    FUN = function(x) {
      return(ShiftCell(bin = bin, x = all.comb[x, 1], y = all.comb[x, 2]))
    }))))
}

#FetchClosest bin, used internally in spatial mapping
FetchClosest <- function(bin, all.centroids, num.cell) {
  bin.y <- (bin - 1) %/% 8 + 1
  bin.x <- (bin - 1) %% 8 + 1
  all.centroids <- rbind(all.centroids, c(bin.x, bin.y))
  all.dist <- as.matrix(x = dist(x = all.centroids))
  return(names(x = sort(x = all.dist[nrow(x = all.dist), ]))[2:(num.cell + 2)])
}

#calculate refined mapping probabilites based on multivariate distribution
slimdmvnorm <- function (x, mean = rep(0, p), sigma = diag(p), log = FALSE) {
  x <- matrix(data = x, ncol = length(x = x))
  p <- ncol(x = x)
  dec <- tryCatch(chol(x = sigma), error = function(e) e)
  tmp <- backsolve(r = dec, t(x = x) - mean, transpose = TRUE)
  rss <- colSums(tmp ^ 2)
  logretval <- -sum(log(x = diag(x = dec))) - 0.5 * p * log(x = 2 * pi) - 0.5 * rss
  names(x = logretval) <- rownames(x = x)
  return(logretval)
}


# Documentation
###############
#Internal, not documented for now
CalcInsitu <- function(
  object,
  gene,
  do.plot = TRUE,
  do.write = FALSE,
  write.dir = "~/window/insitu/",
  col.use = bwCols,
  do.norm = FALSE,
  cells.use = NULL,
  do.return = FALSE,
  probs.min = 0,
  do.log = FALSE,
  use.imputed = FALSE,
  bleach.use = 0
) {
  cells.use <- SetIfNull(x = cells.use, default = colnames(x = object@spatial@final.prob))
  probs.use <- object@spatial@final.prob
  if (use.imputed) {
    data.use <- exp(x = object@imputed) - 1
  } else {
    data.use <- exp(object@data) - 1
  }
  cells.use <- cells.use[cells.use %in% colnames(x = probs.use)]
  cells.use <- cells.use[cells.use %in% colnames(x = data.use)]
  #insilico.stain=matrix(unlist(lapply(1:64,function(x) sum(probs.use[x,]*data.use[gene,]))),nrow=8,ncol=8)
  insilico.vector <- unlist(
    x = lapply(
      X = 1:64,
      FUN = function(x) {
        return(sum(
          as.numeric(x = probs.use[x, cells.use]) *
            as.numeric(x = data.use[gene, cells.use])
        ))
      }
    )
  )
  probs.total <- apply(X = probs.use, MARGIN = 1, FUN = sum)
  probs.total[probs.total < probs.min] <- probs.min
  insilico.stain <- (matrix(data = insilico.vector / probs.total, nrow=8, ncol=8))
  if (do.log) {
    insilico.stain <- log(x = insilico.stain + 1)
  }
  if (bleach.use > 0) {
    insilico.stain <- insilico.stain - bleach.use
    insilico.stain <- MinMax(data = insilico.stain, min=0, max=1e6)
  }
  if (do.norm) {
    insilico.stain <- (insilico.stain - min(insilico.stain)) /
      (max(insilico.stain) - min(insilico.stain))
  }
  title.use <- gene
  if (gene %in% colnames(x = object@spatial@insitu.matrix)) {
    pred.use <- prediction(
      predictions = insilico.vector / probs.total,
      labels = object@spatial@insitu.matrix[, gene],
      label.ordering = 0:1
    )
    perf.use <- performance(prediction.obj = pred.use, measure = "auc")
    auc.use <- round(x = perf.use@y.values[[1]], digits = 3)
    title.use <- paste(gene, sep=" ")
  }
  if (do.write) {
    write.table(
      x = insilico.stain,
      file = paste0(write.dir, gene, ".txt"),
      quote=FALSE,
      row.names=FALSE,
      col.names=FALSE
    )
  }
  if (do.plot) {
    aheatmap(
      x = insilico.stain,
      Rowv = NA,
      Colv = NA,
      col = col.use,
      main=title.use
    )
  }
  if (do.return) {
    return(as.vector(x = insilico.stain))
  }
  return(object)
}



# Documentation
###############
#Not documented for now
#' @export
PosteriorPlot <- function(object, name) {
  post.names <- colnames(x = SubsetColumn(data = object@spatial@mix.probs, code = name))
  VlnPlot(
    object = object,
    features.plot = post.names,
    inc.first=TRUE,
    inc.final=TRUE,
    by.k=TRUE
  )
}

# Documentation
###############
#Internal, not documented for now
map.cell.score <- function(gene, gene.value, insitu.bin, mu, sigma, alpha) {
  code.1 <- paste(gene, insitu.bin, sep=".")
  mu.use <- mu[paste(code.1, "mu", sep="."), 1]
  sigma.use <- sigma[paste(code.1, "sigma", sep="."), 1]
  alpha.use <- alpha[paste(code.1, "alpha", sep="."), 1]
  bin.prob <- unlist(
    x = lapply(
      X = 1:length(x = insitu.bin),
      FUN = function(x) {
        return(dnorm(
          x = gene.value,
          mean = mu.use[x],
          sd = sigma.use[x],
          log = TRUE) + log(x = alpha.use[x])
        )
      }
    )
  )
  return(bin.prob)
}

#Internal, not documented for now
#' @export
#'
MapCell <- function(
  object,
  cell.name,
  do.plot = FALSE,
  safe.use = TRUE,
  text.val = NULL,
  do.rev = FALSE
) {
  insitu.matrix <- object@spatial@insitu.matrix
  insitu.genes <- colnames(x = insitu.matrix)
  insitu.genes <- insitu.genes[insitu.genes %in% rownames(x = object@imputed)]
  insitu.use <- insitu.matrix[, insitu.genes]
  imputed.use <- object@imputed[insitu.genes, ]
  if (safe.use) {
    safe_fxn <- LogAdd
  } else {
    safe_fxn <- sum
  }
  all.needed.cols <- unique(
    x = unlist(
      x = lapply(
        X = insitu.genes,
        FUN = function(x) {
          return(paste(x, insitu.use[, x], "post", sep="."))
        }
      )
    )
  )
  missing.cols <- which(! (all.needed.cols %in% colnames(x = object@spatial@mix.probs)))
  if (length(x = missing.cols) > 0) {
    stop(paste(
      "Error: ",
      all.needed.cols[missing.cols],
      "is missing from the mixture fits"
    ))
  }
  all.probs <- data.frame(
    sapply(
      X = insitu.genes,
      FUN = function(x) {
        return(
          log(x = as.numeric(x = object@spatial@mix.probs[
            cell.name, # Row
            paste(x, insitu.use[, x], "post", sep=".") # Column
            ])))
      }
    )
  )
  scale.probs <- t(
    x = t(x = all.probs) - apply(X = t(x = all.probs), MARGIN = 1, FUN = LogAdd)
  )
  scale.probs[scale.probs < (-9.2)] <- (-9.2)
  #head(scale.probs)
  total.prob <- exp(x = apply(X = scale.probs, MARGIN = 1, FUN = safe_fxn))
  total.prob <- total.prob / sum(total.prob)
  if (do.plot) {
    #plot(total.prob,main=cell.name)
    par(mfrow = c(1, 2))
    txt.matrix <- matrix(data = rep(x = "", 64), nrow=8, ncol=8)
    if (! is.null(x = text.val)) {
      txt.matrix[text.val] <- "X"
    }
    if (do.rev) {
      scale.probs <- scale.probs[unlist(
        x = lapply(
          X = 0:7,
          FUN = function(x) {
            return(seq(from = 1, to = 57, by = 8) + x)
          }
        )
      ), ]
    }
    aheatmap(
      x = matrix(data = total.prob, nrow=8, ncol=8),
      Rowv = NA,
      Colv = NA,
      txt = txt.matrix,
      col = bwCols
    )
    aheatmap(x = scale.probs, Rowv = NA, Colv = NA)
    ResetPar()
  }
  return(total.prob)
}

# Set up class to hold spatial info
spatial.info <- setClass(
  Class = "spatial.info",
  slots = list(
    mix.probs = "data.frame",
    mix.param = "data.frame",
    final.prob = "data.frame",
    insitu.matrix = "data.frame"
  )
)

#Internal, not documented for now
iter.k.fit <- function(scale.data, cell.ident, data.use) {
  means.all <- sapply(
    X = sort(x = unique(x = cell.ident)),
    FUN = function(x) {
      return(apply(X = scale.data[, cell.ident == x], MARGIN = 1, FUN = mean))
    }
  )
  all.dist <- data.frame(
    t(x = sapply(
      X = 1:ncol(x = scale.data),
      FUN = function(x) {
        return(unlist(x = lapply(
          X = sort(x = unique(x = cell.ident)),
          FUN = function(y) {
            return(dist(x = rbind(scale.data[, x], means.all[, y])))
          }
        )))
      }
    ))
  )
  cell.ident <- apply(X = all.dist, MARGIN = 1, FUN = which.min)
  cell.ident <- order(tapply(
    X = as.numeric(x = data.use),
    INDEX = cell.ident,
    FUN = mean
  ))[cell.ident]
  return(cell.ident)
}
