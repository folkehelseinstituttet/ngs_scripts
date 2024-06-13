library(Rsamtools)
# Index the fasta file
# Tror det er mulig å indexe gzippa fil??
#suppressMessages(indexFa(file = "/media/jonr/SATA6TB/Gisaid/sequences.fasta"))
indexFa(file = "/mnt/tempdata/nextstrain/sequences.fasta")
