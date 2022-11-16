#V2. Insertions detection


library(tidyverse)
library(GenomicAlignments)
library(reshape2)
library(msa)
library(seqinr)
library(writexl)
library("doParallel")
library("parallel")
library("foreach")
library(doSNOW)
library(progress)


DeletionFinder<-function(reference = "/home/docker/CommonFiles/nCoV-2019.reference.fasta",
                         cores=10,
                         total.fasta,
                         results.folder="/media/nacho/Data/NSC/GISAID/",
                         algorithm="Muscle",
                         genelist="/home/docker/CommonFiles/corona genemap.csv"
                         ){

  #Loop to deal with multiple fasta and transform them into a multifasta
  if(length(total.fasta)>1){
    for (i in 1:length(total.fasta)) {
      dummy<-read.fasta(total.fasta[i])
      if(!exists("out.fasta")){
        out.fasta<-dummy  
      }else{
        out.fasta<-c(out.fasta, dummy)
      }
    }
    write.fasta(out.fasta, names = names(out.fasta), paste(results.folder,"multifasta.fa",sep = ""))
    total.fasta<-paste(results.folder,"multifasta.fa",sep = "")
  }
  
  #Deletion of samples with less than 10 nucleotides
  test.length<-read.fasta(total.fasta)
f.length<-as.numeric(lapply(test.length, length))
if(length(which(f.length<10))>0){
  test.length<-test.length[-which(f.length<10)] 
  write.fasta(test.length, paste(total.fasta,"_clean.fasta", sep = ""),names =names(test.length) )
  total.fasta<-paste(total.fasta,"_clean.fasta", sep = "")
}

  
# Fasta files comparison and mutations extraction --------------------------------------------------

  genes<-read.csv(genelist)
  non.codding<-c(1:29903)
  
for (i in 1:nrow(genes)) {
  non.codding<-non.codding[-which(non.codding %in% c(genes$start[i]:genes$end[i]))]
}
  
seq.list<-readDNAStringSet(c(total.fasta, reference))  
names(seq.list)<-gsub(" MN908947.3", "", names(seq.list))
samples<-names(seq.list)[-length(seq.list)]

samples.to.analyze<-samples

pb <- progress_bar$new(
  format = "Sample: :samp.pb [:bar] :elapsed | eta: :eta",
  total = length(samples.to.analyze),    # 100 
  width = 60)

samp <- samples.to.analyze

progress <- function(n){
  pb$tick(tokens = list(samp.pb = samp[n]))
} 

opts <- list(progress = progress)


###
gc()
cores.n<-detectCores()
if(cores>cores.n) cores<- cores.n -2
if(cores>length(samples)) cores<-length(samples)
cluster.cores<-makeCluster(cores)
registerDoSNOW(cluster.cores)


out.par<-foreach(k=1:length(samples.to.analyze), .verbose=FALSE, .packages = c("msa", "reshape2"),.options.snow = opts) %dopar%{
  
    seq.aln<-msa(seq.list[c(k,length(seq.list))], algorithm)
    x<-DNAMultipleAlignment(seq.aln)
    DNAStr = as(x, "DNAStringSet")
    #seq<-toupper(as.character(DNAStr[grep(samples.to.analyze[k],names(DNAStr))]))
    seq<-toupper(as.character(DNAStr[-grep(names(seq.list)[length(seq.list)],names(DNAStr))]))    
    
    results<-as.data.frame(matrix(nrow = 1, ncol = 4))
    colnames(results)<-c("Sample","Deletions","Frameshift", "Insertions")
    results$Frameshift<-"NO"
    results$Insertions<-"NO"
    
    seq.reference<-unlist(base::strsplit(as.character(DNAStr[grep(names(seq.list)[length(seq.list)],names(DNAStr))]),""))
    if(length(seq.reference[seq.reference=="-"])!=0){
      results$Insertions<-paste(as.numeric(which(seq.reference=="-")), collapse = " / ")
      
      ins.n<-length(seq.reference[seq.reference=="-"])
      ins.fs<-"YES"
      if(which(seq.reference=="-")==29904) ins.fs<-"NO" 
      if(length(which(as.numeric(which(seq.reference=="-")) %in% non.codding )) == length(which(seq.reference=="-"))) ins.fs<-"NO"
    }else{
      ins.fs<-"NO"
      ins.n<-0
    }
   
    
    if(ins.n>0){
      fram.s.insertio<-ins.n%%3
      if(fram.s.insertio!=0){
        results$Frameshift<-"YES"
      }else{
        if(max(as.numeric(which(seq.reference=="-")))-min(as.numeric(which(seq.reference=="-")))> length(as.numeric(which(seq.reference=="-")))){
          results$Frameshift<-"YES"
        }
      }
    }
    if(ins.fs=="NO")results$Frameshift<-"NO"
    
    out.df<-as.data.frame(matrix(data = NA, nrow = 36, ncol = 4))
    colnames(out.df)<-c("Length", "Elements", "Positions","FS")
    out.df$Length<-c(1:36)
    
    for (i in 1:nrow(out.df)) {
      dummy<-unlist(base::strsplit(seq, paste("[A-Z]\\-{",i,"}[A-Z]",sep = "")))
      
      out.df$Elements[i]<-length(dummy)-1  
      if(length(dummy)>1){
        
        dummy<-dummy[-length(dummy)]
        characters<-as.numeric(nchar(dummy))
        characters[1]<-characters[1]+2
        if(length(dummy)>1){
          for(j in 2:(length(characters))){
            characters[j] <- characters[j-1]+characters[j] + 2 +i 
          }
        }
        
        if(ins.n>0){
          for (c in 1:length(characters)) {
            characters[c] <- characters[c]- length(which(as.numeric(which(seq.reference=="-"))<characters[c]))
          }
        }
        
        out.df$Positions[i]<-paste(characters,collapse = ";")
        if(length(which(characters %in% non.codding))==length(characters)){ 
          out.df$FS[i]<-"NO"
        }else{
          out.df$FS[i]<-"YES"  
        }
      }

      
    }
    
    out.df$To.out<-paste(out.df$Length, "[", out.df$Positions,"]", sep = "")
    out.df$To.out[out.df$Elements==0]<-NA
    
    results$Deletions<-paste(na.omit(out.df$To.out), collapse = " / ")
    results$Sample<-samples.to.analyze[k]
    deletion.lengh<-out.df$Length[out.df$Elements!=0]%%3
    if(length(which(deletion.lengh>0))>0 & length(which(out.df$FS=="YES"))>0){
      results$Frameshift<-"YES"
    }
    
    return(results)
}

stopCluster(cluster.cores)

try(rm(final.results))
for (i in 1:length(out.par)) {
  dummy<-out.par[[i]]
  
  if(!exists("final.results")){
    final.results<-dummy
  }else{
    final.results<-rbind(final.results, dummy)
  } 
}
date<-gsub("-","",Sys.Date())


write.csv(final.results, paste(results.folder, date, "DeletionFinderResults.csv",sep = ""), row.names = FALSE)
return(final.results)
}