library(sangeranalyseR)

data <- "N:/Virologi/Hepatitt/Hepatitt B/HBV genotyping/2025/HBSPCR1-0103-1/Sekvenseringsfiler"

contigs <- SangerAlignment(ABIF_Directory     = data,
                           REGEX_SuffixForward = "_s-adet[A-H][0-9]{2}\\.ab1$", # Bruke alt før "_S" som sample name. "adet" er Fwd
                           REGEX_SuffixReverse = "_s-Bsc2[A-H][0-9]{2}\\.ab1$") # Bruke alt før "_S" som sample name. "Bsc2" er Rev


launchApp(contigs)

writeFasta(contigs,
           outputDir = "sanger/")

generateReport(contigs,
               outputDir = "sanger/")
