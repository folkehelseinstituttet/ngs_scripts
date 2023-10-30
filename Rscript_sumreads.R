.libPaths("/home/ngs/miniconda3/lib/R/library")

args = commandArgs(trailingOnly=TRUE)

df<-read.csv(file=args[1], header=TRUE, sep="\t", dec=".")

# df<-read.delim(file="Q-3a-1x-2-R_S37_ICTV_tanoti_stats.txt", sep="\t", dec=".")

dat1 <- data.frame(do.call(rbind, strsplit(as.vector(df$ReferenceID), split = "_")))
colnames(dat1)<-c("Genotype", "ID")

df_full<-cbind(df, dat1)

sum_reads<-aggregate(MappedReads ~ Genotype, df_full, sum)
sum_reads$MappedReads<-as.numeric(sum_reads$MappedReads)
sum_reads<-sum_reads[order(sum_reads$MappedReads, decreasing=TRUE),]

sum_reads$Percent<-sum_reads$MappedReads / sum(sum_reads$MappedReads)

write.table(sum_reads, file=args[2], row.names=FALSE)