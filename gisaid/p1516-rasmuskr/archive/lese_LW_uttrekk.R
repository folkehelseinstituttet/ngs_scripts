# List relevant files
files <- list.files(path = "G:/Lab/Rapporter/FluRes-BN/",
                    pattern = "^AK_ILAB_Flures_\\d+_.*csv$", # \\d+ matches one or more digits. This is to avoid the FNR files
                    full.names = TRUE)


# Loop through the files, read them and select relevant samples and columns. Them merge everything to one large data frame


# Gisaid ------------------------------------------------------------------
# Create empty df to populate
final_df <- data.frame(Stammenavn_pr = character(0))

pb <- txtProgressBar(min = 0, max = length(files), initial = 0)
for (i in 1:length(files)) {
  setTxtProgressBar(pb, i)
  tmp_df <- read.csv(file = files[i],
                     sep = ";",
                     header = TRUE)
  
  # Keep only SARS-CoV-2 samples and samples that are "svart ut" (approved)
  if (nrow(tmp_df) > 0) {
    sc2 <- tmp_df[which(tmp_df$Analyse_resultat == "SARS-CoV-2"),]
  }
  
  if (exists("sc2")) {
    if (nrow(sc2) > 0) {
      sc2_2 <- sc2[which(sc2$Test_status == "A"),]
    }
  }
  
  if (exists("sc2_2")) {
    if (nrow(sc2_2) > 0) {
      # Hente ut Stammenavn_prøve og trekke ut prÃ¸vene fra tmp_df
      #NB Bruke Ordrenummer eller prøvenummer isteden? Blir så innmari mange like med Stammenavn_prøve...
      stammenavn <- unique(sc2_2$Stammenavn_prÃ.ve)
      
      keep <- tmp_df$Stammenavn_prÃ.ve %in% stammenavn
      
      subset <- tmp_df[keep, ]
      
      # Beholde kun stammenavn_prøve
      final <- unique(subset$Stammenavn_prÃ.ve)
      
      final <- as.data.frame(final)
      
      colnames(final) <- "Stammenavn_pr"
    }
  }
  
  # Combine with the final data frame
  if (exists("final")) {
    final_df <- rbind(final_df, final)
  }
  
  close(pb)
}

# Write final_df as a tsv file for ordinÃ¦r sone
write.table(final_df,
            file = paste0("J:/", format(Sys.Date(), "%Y.%m.%d"), "-SARS-CoV-2_stammenavn_approved_in_LW.tsv"),
            sep = "\t",
            quote = FALSE,
            row.names = FALSE)

# FHI Statistikk ----------------------------------------------------------
# 
# 
# # Create empty df to populate
# final_df <- data.frame(LW_nr = numeric(0),
#                        Stammenavn_rekv = character(0),
#                        Born_year = numeric(0),
#                        Born_month = numeric(0),
#                        Gender = character(0),
#                        Fylke = character(0),
#                        Sample_date = character(0),
#                        Analyse = character(0),
#                        Komponent = character(0),
#                        Analyse_resultat = character(0))
# 
# pb <- txtProgressBar(min = 0, max = length(files), initial = 0)
# for (i in 1:length(files)) {
#   setTxtProgressBar(pb, i)
#   tmp_df <- read.csv(file = files[i],
#                      sep = ";",
#                      header = TRUE)
# 
#   # Keep only SARS-CoV-2 samples and samples that are "svart ut" (approved)
#   if (nrow(tmp_df) > 0) {
#     sc2 <- tmp_df[which(tmp_df$Analyse_resultat == "SARS-CoV-2"),]
#   }
# 
#   if (exists("sc2")) {
#     if (nrow(sc2) > 0) {
#       sc2_2 <- sc2[which(sc2$Test_status == "A"),]
#     }
#   }
# 
#   if (exists("sc2_2") & nrow(sc2_2) > 0) {
#     # Hente ut Stammenavn_prøve og trekke ut prÃ¸vene fra tmp_df
#     #NB Bruke Ordrenummer eller prøvenummer isteden? Blir så innmari mange like med Stammenavn_prøve...
#     stammenavn <- unique(sc2_2$Stammenavn_prÃ.ve)
# 
#     keep <- tmp_df$Stammenavn_prÃ.ve %in% stammenavn
# 
#     subset <- tmp_df[keep, ]
# 
#     # Beholde relevante kolonner
#     final <- subset[, c("PrÃ.venr", "Stammenavn_rekv", "FÃ.dtÃ.r", "FÃ.dtmnd", "KjÃ.nn", "Fylke", "PrÃ.ve_tatt", "Analyse", "Komponent", "Analyse_resultat")]
# 
#     # Check that the correct columns have been selected or are present
#     if(identical(colnames(final), c("PrÃ.venr", "Stammenavn_rekv", "FÃ.dtÃ.r", "FÃ.dtmnd", "KjÃ.nn", "Fylke", "PrÃ.ve_tatt", "Analyse", "Komponent", "Analyse_resultat"))) {
# 
#       # Rename the columns before merging
#       colnames(final) <- colnames(final_df)
#     }
#   }
# 
#   # Combine with the final data frame
#   if (exists("final")) {
#     final_df <- rbind(final_df, final)
#   }
# 
#   close(pb)
# }
# 
# # Remove the LW_nr column before saving to ordinÃ¦r sone
# final_df <- subset(final_df, select = -LW_nr)
# 
# # Write final_df as a tsv file for ordinÃ¦r sone
# write.table(final_df,
#             file = paste0("J:/", format(Sys.Date(), "%Y.%m.%d"), "-SARS-CoV-2_samples_approved_in_LW.tsv"),
#             sep = "\t",
#             quote = FALSE,
#             row.names = FALSE)
