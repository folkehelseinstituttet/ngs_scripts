library(officer)
extract_titles <- function(path){
  doc <- read_pptx(path)
  n <- length(doc)
  slide <- integer()
  title <- character()
  for(i in seq_len(n)){
    ss <- slide_summary(doc, index=i)
    if(!all(c('type','text') %in% names(ss))) next
    idx <- which(ss$type == 'title' & !is.na(ss$text) & trimws(ss$text) != '')
    if(length(idx) > 0){
      slide <- c(slide, rep(i, length(idx)))
      title <- c(title, as.character(ss$text[idx]))
    }
  }
  data.frame(slide=slide, title=title, stringsAsFactors=FALSE)
}
flu <- extract_titles('N:/Virologi/Influensa/2526/WGS_Analyse/Results/Influenza__Week.20-2026_result.pptx')
sc2 <- extract_titles('N:/Virologi/Influensa/2526/WGS_Analyse/Results/SARSCOV2_2026_Week20_result.pptx')
write.csv(flu, 'tmp_flu_titles_full.csv', row.names=FALSE, fileEncoding='UTF-8')
write.csv(sc2, 'tmp_sc2_titles_full.csv', row.names=FALSE, fileEncoding='UTF-8')
cat('FLU_N=', nrow(flu), ' SC2_N=', nrow(sc2), '\n', sep='')
key_pat <- 'Population Under Surveillance|Patient Related Analysis|Map:|Kjonn|Alder|Fylke|Landsdel|status|Sample category'
cat('--- FLU PATIENT/REGION TITLES ---\n')
print(flu[grepl(key_pat, flu$title, ignore.case=TRUE), ])
cat('--- SC2 PATIENT/REGION TITLES ---\n')
print(sc2[grepl(key_pat, sc2$title, ignore.case=TRUE), ])
cat('--- SC2 NOT IN FLU (UNIQUE TITLE TEXT) ---\n')
print(setdiff(unique(sc2$title), unique(flu$title)))
cat('--- FLU NOT IN SC2 (UNIQUE TITLE TEXT) ---\n')
print(setdiff(unique(flu$title), unique(sc2$title)))
