#!/usr/bin/env Rscript

# Script modified from:
#Corona Swiss-Army-Knife Docker Image
#Nacho Garcia 2021 / iggl@fhi.no

library(seqinr)
library(writexl)
library(readxl)
library(tidyverse)
library(GenomicAlignments)
library(reshape2)
library(msa)
library("doParallel")
library("parallel")
library("foreach")
library(doSNOW)
library(progress)

args=commandArgs(TRUE)

# Open connection to log file
log_file <- file(paste0(Sys.Date(), "_frameshift.log"), open = "a")

cores <- as.numeric(args[1])
results.folder <- paste0(args[2], "/")
multifasta <- args[3]
reference <- "https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/nCoV-2019.reference.fasta"
genelist <- "https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/corona%20genemap.csv"
# Frameshift database: https://github.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/tree/master/CommonFiles/FSDB
# Remember to update
database <- "https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/FSDB/FSDB20220718.csv"

########################################################################################################################
### Define Deletion Finder function                                                                                  ###
### Taken from the script CSAK_DeletionFinder_v05.R                                                                  ###
### https://github.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/blob/master/Scripts/CSAK_DeletionFinder_v05.R ###
########################################################################################################################




DeletionFinder<-function(reference = "https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/nCoV-2019.reference.fasta",
                         cores,
                         total.fasta,
                         results.folder,
                         algorithm = "Muscle",
                         genelist = "https://raw.githubusercontent.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/master/CommonFiles/corona%20genemap.csv"
){
  
  #  #Loop to deal with multiple fasta and transform them into a multifasta
  #  if(length(total.fasta)>1){
  #    for (i in 1:length(total.fasta)) {
  #      dummy<-read.fasta(total.fasta[i])
  #      if(!exists("out.fasta")){
  #        out.fasta<-dummy  
  #      }else{
  #        out.fasta<-c(out.fasta, dummy)
  #      }
  #    }
  #    write.fasta(out.fasta, names = names(out.fasta), paste(results.folder,"multifasta.fa",sep = ""))
  #    total.fasta<-paste(results.folder,"multifasta.fa",sep = "")
  #  }
  
  #  #Deletion of samples with less than 10 nucleotides
  #  test.length<-read.fasta(total.fasta)
  #f.length<-as.numeric(lapply(test.length, length))
  #if(length(which(f.length<10))>0){
  #  test.length<-test.length[-which(f.length<10)] 
  #  write.fasta(test.length, paste(total.fasta,"_clean.fasta", sep = ""),names =names(test.length) )
  #  total.fasta<-paste(total.fasta,"_clean.fasta", sep = "")
  #}
  
  
  # Fasta files comparison and mutations extraction --------------------------------------------------
  
  genes <- read.csv(genelist)
  non.codding <- c(1:29903)
  
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
  #cores.n<-detectCores()
  #if(cores>cores.n) cores <- cores.n -2
  if(cores>length(samples)) cores <- length(samples)
  cluster.cores<-makeCluster(cores)
  registerDoSNOW(cluster.cores)
  
  
  out.par<-foreach(k=1:length(samples.to.analyze), .verbose=FALSE, .packages = c("msa", "reshape2"),.options.snow = opts) %dopar%{
    
    # Aligne en og en sekvens (k) mot den siste sekvensen i lista (referansen) (length(seq.list))
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

####################################
### Deletion Finder function end ###
####################################

######################################
### Start the Frame Shift analysis ###
######################################

# Run Deletion Finder
deletion_results <- DeletionFinder(total.fasta = multifasta,
               results.folder = results.folder,
               cores = cores,
               reference = reference,
               genelist = genelist)

genes <- read.csv(genelist)
non.codding <- c(1:29903)
for (i in 1:nrow(genes)) {
  non.codding<-non.codding[-which(non.codding %in% c(genes$start[i]:genes$end[i]))]
}


#Cleaning

deletion_results$Frameshift[which(deletion_results$Deletions=="1[28271] / 3[21991] / 6[21765] / 9[11288]" & deletion_results$Insertions=="NO")]<-"NO"

#Check insertions and deletion region of genes
positions.to.test<-list()
for (i in 1:nrow(deletion_results)) {
  if(deletion_results$Insertions[i]=="NO" & deletion_results$Frameshift[i]=="YES"){
    dummy<-unlist(base::strsplit(deletion_results$Deletions[i],"/"))
    del.check<-FALSE
    for (j in 1:length(dummy)) {
      size<-as.numeric(gsub("\\[.*", "",dummy[j]))
      
      if(size%%3 !=0){
        positions.del<-gsub("\\].*","",gsub(".*\\[","",dummy[j]))
        positions.del<-as.numeric(unlist(base::strsplit(positions.del,";")))
        if(length(positions.del)==length(positions.del[which(positions.del %in% non.codding)]) & deletion_results$Insertions[i]=="NO"){
          if(!del.check) deletion_results$Frameshift[i]<-"NO"
          rm(positions.del)
        }else{
          if(length(positions.del[which(positions.del %in% non.codding)])>0) positions.del<-positions.del[-which(positions.del %in% non.codding)]
          if(length(positions.to.test)==0) positions.to.test[[1]]<-positions.del
          if(length(positions.to.test)>0)positions.to.test[[length(positions.to.test)]]<-c(positions.to.test[[length(positions.to.test)]],positions.del)
          deletion_results$Frameshift[i]<-"YES"
          del.check<-TRUE
        }
      }
      
      
    }
    if(deletion_results$Insertions[i]=="NO" & deletion_results$Frameshift[i]=="YES"){
      names(positions.to.test)[length(positions.to.test)]<-deletion_results$Sample[i]
    }  
  }
  
}

deletion_results<-deletion_results[order(deletion_results$Frameshift, decreasing = TRUE),]
write_xlsx(deletion_results[,c(1:4)],paste(results.folder,"FrameShift_", gsub("\\.fa.*","",gsub(".*/","", multifasta)),".xlsx",sep = ""))


# FrameshiftDB ------------------------------------------------------------

#database<-list.files("/home/docker/CommonFiles/FSDB/",full.names = TRUE, pattern = "FSDB.*.csv")
if(length(database)>0){
  
  indels<-read.csv(database)
  inputfile<- paste(results.folder,"FrameShift_", gsub("\\.fa.*","",gsub(".*/","", multifasta)),".xlsx",sep = "")
  df<-read_xlsx(inputfile)
  df.ready<-df[which(df$Frameshift=="NO"),]
  df.ready$Ready<-"YES"
  df.ready$Comments<-"No frameshifts detected"
  
  if(length(which(df$Frameshift=="YES"))>0){
  
  df<-df[which(df$Frameshift=="YES"),]
  df$Ready<-"NO"
  df$Comments<-NA
  
  indels<-indels[which(indels$Status=="Confirmed Fastq"),]
  
  insertion.list<-gsub(".*: ","",indels$ID[grep("Insertion",indels$ID)])
  deletion.list<-gsub(".*: ","",indels$ID[grep("Deletion",indels$ID)])
  
  for (i in 1:nrow(df)) {
    flag<-NA
    dummy.ins<-gsub(" ","",unlist(base::strsplit(df$Insertions[i],"/")))
    dummy.dels<-gsub(" ","",unlist(base::strsplit(df$Deletions[i],"/")))
    
    if(length(dummy.ins[which(dummy.ins %in% insertion.list)])!=length(dummy.ins) & dummy.ins[1]!="NO"){
      
      if(length(dummy.ins)>1){ 
        df$Comments[i]<-paste("Unknown insertion/s detected at", paste(dummy.ins[-which(dummy.ins %in% insertion.list)], collapse = ";"))
        if(length(which(dummy.ins %in% insertion.list))==0){
        df$Comments[i]<-paste("Unknown insertion/s detected at", paste(dummy.ins,collapse = ","))
        }
        
      }else{
        df$Comments[i]<-paste("Unknown insertion/s detected at", dummy.ins)
      }
      flag<-"InsKO"
    }else{
      flag<-"InsOK"
    }
    
    to.clean<-dummy.dels[grep(";", dummy.dels)]
    
    if(length(to.clean)>0){
      dummy.dels<-dummy.dels[-grep(";", dummy.dels)]
      for (j in 1:length(to.clean)) {
        dummy.dels2<-unlist(base::strsplit(to.clean[j],";"))
        dummy.dels2[-1]<- paste(gsub("\\[.*","[",dummy.dels2[1]), dummy.dels2[-1],sep = "")
        dummy.dels2<-paste(dummy.dels2,"]",sep = "")
        dummy.dels2<-gsub("]]","]",dummy.dels2)
        dummy.dels<-c(dummy.dels2, dummy.dels)
      }
    }
    dummy.dels<-dummy.dels[which(as.numeric(gsub("\\[.*","",dummy.dels))%%3 !=0 )]
    
    if(length(dummy.dels)==0 & is.na(df$Comments[i]) ){
      #No deletions FS and all Insertions are OK
      df$Ready[i]<-"YES"
      df$Comments[i]<-"All frameshifts are OK"
    }
    
    #INS OK / DELS Ok
    if(length(dummy.dels)>0){
      if(length(dummy.dels[which(dummy.dels %in% deletion.list)])==length(dummy.dels) & flag=="InsOK" ){
        df$Ready[i]<-"YES"
        df$Comments[i]<-"All frameshifts are OK"
      }
      
      #INS OK /DELS KO
      if(length(dummy.dels[which(dummy.dels %in% deletion.list)])!=length(dummy.dels) & flag=="InsOK" ){
        df$Ready[i]<-"NO"
        if(length(dummy.dels)>1){ 
          if(length(which(dummy.dels %in% deletion.list))>0){
          df$Comments[i]<-paste("Unknown deletions/s detected at", paste(dummy.dels[-which(dummy.dels %in% deletion.list)], collapse = ";"))
          }else{
            df$Comments[i]<-paste("Unknown deletions/s detected at", paste(dummy.dels,collapse = ","))
          }
        }else{
          df$Comments[i]<-paste("Unknown deletions/s detected at", dummy.dels)
        }
        flag<-"InsOK_DelKO"
      }
      
      #INS KO /DELS KO
      if(length(dummy.dels[which(dummy.dels %in% deletion.list)])!=length(dummy.dels) & flag=="InsKO" ){
        df$Ready[i]<-"NO"
        if(length(dummy.dels)>1){ 
          df$Comments[i]<-paste(df$Comments[i], "&", paste("Unknown deletions/s detected at", paste(dummy.dels[-which(dummy.dels %in% deletion.list)], collapse = ";")))
        }else{
          df$Comments[i]<-paste(df$Comments[i], "&", paste("Unknown deletions/s detected at", dummy.dels))
        }
      }
      
      
      
      
      
    }
  }
  df$Comments<-gsub("NA & ","",df$Comments)
  df<-rbind(df, df.ready)
  }else{
    df<-df.ready
  }
  
  write_xlsx(df,inputfile)
  
}

close(log_file)

# Write out sessionInfo() to track versions
session <- capture.output(sessionInfo())
write_lines(session, file = paste0(Sys.Date(), "_R_versions_frameshift.txt"))