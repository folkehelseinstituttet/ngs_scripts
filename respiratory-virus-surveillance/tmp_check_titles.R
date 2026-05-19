library(officer)
contains_phrase <- function(path, phrase){
  doc <- read_pptx(path)
  n <- length(doc)
  hits <- data.frame(slide=integer(), text=character(), stringsAsFactors=FALSE)
  for(i in seq_len(n)){
    ss <- slide_summary(doc, index=i)
    if(!('text' %in% names(ss))) next
    idx <- which(!is.na(ss$text) & grepl(phrase, ss$text, ignore.case=TRUE))
    if(length(idx)>0){
      hits <- rbind(hits, data.frame(slide=rep(i,length(idx)), text=as.character(ss$text[idx]), stringsAsFactors=FALSE))
    }
  }
  hits
}
sc2 <- 'N:/Virologi/Influensa/2526/WGS_Analyse/Results/SARSCOV2_2026_Week20_result.pptx'
flu <- 'N:/Virologi/Influensa/2526/WGS_Analyse/Results/Influenza__Week.20-2026_result.pptx'
h_sc2 <- contains_phrase(sc2, 'last 6 months')
h_flu <- contains_phrase(flu, 'last 6 months')
cat('SC2 last-6-month hits:', nrow(h_sc2), '\n')
if(nrow(h_sc2)>0) print(unique(h_sc2))
cat('FLU last-6-month hits:', nrow(h_flu), '\n')
if(nrow(h_flu)>0) print(unique(h_flu))
