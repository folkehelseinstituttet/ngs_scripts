#!/usr/bin/env Rscript

# Script modified from:
#Corona Swiss-Army-Knife Docker Image
#Nacho Garcia 2021 / iggl@fhi.no

library(seqinr)
library(tidyverse)
library(GenomicAlignments)
library(reshape2)
library(msa)

args=commandArgs(TRUE)

# Open connection to log file
#log_file <- file(paste0(Sys.Date(), "_frameshift.log"), open = "a")

reference      <- args[1] # reference <- "https://raw.githubusercontent.com/jonbra/FHI_Gisaid/master/data/MN908947.3.fasta?token=GHSAT0AAAAAAB55LYB36YE57ZM6WZ52RKU4Y7UT7JA"
genelist       <- args[2] # genelist <- "https://raw.githubusercontent.com/jonbra/FHI_Gisaid/master/data/genemap.csv?token=GHSAT0AAAAAAB55LYB2KWZTO4JJELQ2NXT2Y7UUA3Q"
database       <- args[3] # database <- "https://raw.githubusercontent.com/jonbra/FHI_Gisaid/master/data/FSDB.csv?token=GHSAT0AAAAAAB55LYB2CMJDF23AZV6BKLO6Y7U2RPQ"
total.fasta    <- args[4]
results.folder <- paste0(args[5], "/")
algorithm      <- "Muscle"

########################################################################################################################
### Deletion Finder                                                                                                  ###
### Taken from the script CSAK_DeletionFinder_v05.R                                                                  ###
### https://github.com/folkehelseinstituttet/FHI_SC2_Pipeline_Illumina/blob/master/Scripts/CSAK_DeletionFinder_v05.R ###
########################################################################################################################

# Fasta files comparison and mutations extraction --------------------------------------------------
  
genes <- read.csv(genelist)
non.codding <- c(1:29903)

# Removing positions in coding regions
for (i in 1:nrow(genes)) {
  non.codding <- non.codding[-which(non.codding %in% c(genes$start[i]:genes$end[i]))]
}
  
# Read the reference and the sequence to be aligned
seq.list <- readDNAStringSet(c(total.fasta, reference))  

# Subtract the reference (element 2 in the list)
samples <- names(seq.list)[-length(seq.list)]
  
samples.to.analyze <- samples
 
# Aligne sekvensen mot referansen 
seq.aln <- msa(seq.list[c(1,2)], algorithm)
x <- DNAMultipleAlignment(seq.aln)
DNAStr <- as(x, "DNAStringSet")
    #seq<-toupper(as.character(DNAStr[grep(samples.to.analyze[k],names(DNAStr))]))
# Get the aligned sequence of the sample. Entire sequence as a single vector element. 
seq <- toupper(as.character(DNAStr[-grep(names(seq.list)[length(seq.list)],names(DNAStr))]))    

# Create a data frame to store the results
results <- as.data.frame(matrix(nrow = 1, ncol = 4))
colnames(results) <- c("Sample", "Deletions", "Frameshift", "Insertions")
# Pre-fill frameshifts and insertions with "NO"
results$Frameshift <- "NO"
results$Insertions <- "NO"

# Get the aligned sequence of the reference. Each character as a separate element of a vector
seq.reference <- unlist(base::strsplit(as.character(DNAStr[grep(names(seq.list)[length(seq.list)],names(DNAStr))]),""))

# Update the non coding regions to include the extra reference length as a result of insertions
if(length(seq.reference)>29903) non.codding <- c(non.codding, c((non.codding[length(non.codding)]+1):length(seq.reference)))

# If there are gaps ("-") in the aligned reference sequence (i.e. insertions in the sample):
if(length(seq.reference[seq.reference=="-"])!=0){
  # Get which elements (positions) of the reference that are gaps and write these positions in the Insertions column of results separated by "/"
  results$Insertions <- paste(as.numeric(which(seq.reference=="-")), collapse = " / ")
      
  # ins.n stores the lengt of the insertion
  ins.n <- length(seq.reference[seq.reference=="-"])
  ins.fs <- "YES"
  # If any of the gaps are at position 29904 (i.e. the end), then call NO frameshift
  # if( length(which(seq.reference=="-"))==1 & which(seq.reference=="-")[1]==29904) ins.fs <- "NO" 
  # If ALL? of the insertions are in non-coding regions. Then call NO frameshift.
  if(length(which(as.numeric(which(seq.reference=="-")) %in% non.codding )) == length(which(seq.reference=="-"))) ins.fs <- "NO"
} else {
  ins.fs <- "NO"
  ins.n < -0
}
    
    
if(ins.n > 0){
  fram.s.insertio<-ins.n%%3
  if(fram.s.insertio!=0){
    results$Frameshift<-"YES"
  } else {
    if(max(as.numeric(which(seq.reference=="-")))-min(as.numeric(which(seq.reference=="-")))> length(as.numeric(which(seq.reference=="-")))){
      results$Frameshift<-"YES"
    }
  }
}
    
if(ins.fs=="NO")results$Frameshift<-"NO"
    
out.df <- as.data.frame(matrix(data = NA, nrow = 36, ncol = 4))

colnames(out.df)<-c("Length", "Elements", "Positions","FS")
out.df$Length<-c(1:36)

# Working on the aligned sample sequence
for (i in 1:nrow(out.df)) {

      # Split on increasing number of dashes. E.g. when i <- 6 then the sequence is split where there are 6 dashes
      dummy <- unlist(base::strsplit(seq, paste("[A-Z]\\-{",i,"}[A-Z]",sep = "")))
      
      # If there is a single instance of the gap length then there are two elements in dummy. I.e. Elements <- 1
      out.df$Elements[i] <- length(dummy)-1
      
      if(length(dummy)>1){
        
        # Remove the last element
        dummy <- dummy[-length(dummy)]
        # Number of characters in each element
        characters <- as.numeric(nchar(dummy))
        
        characters[1] <- characters[1]+2
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
    
out.df$To.out <- paste(out.df$Length, "[", out.df$Positions,"]", sep = "")
out.df$To.out[out.df$Elements==0]<-NA
    
results$Deletions <- paste(na.omit(out.df$To.out), collapse = " / ")
results$Sample <- samples.to.analyze
deletion.lengh <- out.df$Length[out.df$Elements!=0]%%3
if(length(which(deletion.lengh > 0)) > 0 & length(which(out.df$FS=="YES"))>0){
      results$Frameshift<-"YES"
}
  
date <- gsub("-","",Sys.Date())
  
# Skip this - instead use the final.results object
#write.csv(final.results, paste(results.folder, date, "DeletionFinderResults.csv",sep = ""), row.names = FALSE)

####################################
### Deletion Finder end ###
####################################



#Cleaning
deletion_results <- results

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

# Skip this as well
#write_xlsx(deletion_results[,c(1:4)],paste(results.folder,"FrameShift_", gsub("\\.fa.*","",gsub(".*/","", total.fasta)),".xlsx",sep = ""))


# FrameshiftDB ------------------------------------------------------------
  
indels <- read.csv(database)
df <- deletion_results

# If the sample has NO frameshifts then it is ready
if(length(which(df$Frameshift=="NO"))>0) {
    df.ready <- df[which(df$Frameshift=="NO"),]
    df.ready$Ready<-"YES"
    df.ready$Comments<-"No frameshifts detected"
}
  
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
} else {
    df <- df.ready
}

# Remove forward slash from sample names before writing.
outfile <- str_replace_all(samples.to.analyze, "/", "_")
write_csv(df, file = paste0("frameshift.csv"), col_names = FALSE)
  

#close(log_file)
