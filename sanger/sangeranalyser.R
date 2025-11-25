library(sangeranalyseR)

data <- "N:/Virologi/Hepatitt/Hepatitt B/HBV genotyping/2025/HBSPCR1-0103-1/Sekvenseringsfiler"

contigs <- SangerAlignment(ABIF_Directory       = data,
                           REGEX_SuffixForward  = "_s-adet[A-H][0-9]{2}\\.ab1$", # Bruke alt før "_S" som sample name. "adet" er Fwd
                           REGEX_SuffixReverse  = "_s-Bsc2[A-H][0-9]{2}\\.ab1$", # Bruke alt før "_S" som sample name. "Bsc2" er Rev
                           TrimmingMethod       = "M1",
                           M1TrimmingCutoff     = 0.001, # Q 20
                           M2CutoffQualityScore = NULL,
                           M2SlidingWindowSize  = NULL,
                           minReadLength        = 75 # After trimming
                           )


launchApp(contigs)

writeFasta(contigs,
           outputDir = "sanger/",
           compress = FALSE,
           compression_level = NA)

generateReport(contigs,
               outputDir = "sanger/")
