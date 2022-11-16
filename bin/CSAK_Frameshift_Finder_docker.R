#Corona Swiss-Army-Knife Docker Image
#Nacho Garcia 2021 / iggl@fhi.no

library(seqinr)
library(writexl)
library(readxl)

args=commandArgs(TRUE)
 cores<-10
if(length(args)==0){ 
  cores<-10
}else{
  cores<-as.numeric(gsub("c","",args[1]))
  }

#Docker
 results <-"/home/docker/Fastq/"   #Docker
 results<-list.dirs(results)
 if(length(grep("Frameshift",results))>0){
 results<-results[grep("Frameshift",results)]
 results<-paste(results,"/",sep = "")
 result.folder <-results   #Docker
  }else{
    result.folder <- "/home/docker/Fastq/"
 }


common.folder <-"/home/docker/CommonFiles/"
source("/home/docker/Scripts/CSAK_DeletionFinder_v05.R")

# # #Testing
# result.folder <-"/home/nacho/Documents/Corona/CSAK_docker_image/DockerBundling/multisubmit-2021-05-10/"
# common.folder <-"/home/nacho/Documents/Corona/CSAK_docker_image/CommonFiles/"
# source("/home/nacho/Documents/Corona/CSAK_docker_image/Scripts/CSAK_DeletionFinder_v05.R")


multifasta<-list.files(result.folder, pattern = ".*\\.fa.*$", full.names = TRUE)

deletion_results<-DeletionFinder(total.fasta = multifasta,
               results.folder = result.folder,
               cores=cores,
               reference = paste(common.folder,"nCoV-2019.reference.fasta",sep = ""),
               genelist=paste(common.folder,"corona genemap.csv",sep = ""))

genes<-read.csv(paste(common.folder,"corona genemap.csv",sep = ""))
non.codding<-c(1:29903)
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
write_xlsx(deletion_results[,c(1:4)],paste(result.folder,"FrameShift_", gsub("\\.fa.*","",gsub(".*/","", multifasta)),".xlsx",sep = ""))


# FrameshiftDB ------------------------------------------------------------

database<-list.files("/home/docker/CommonFiles/FSDB/",full.names = TRUE, pattern = "FSDB.*.csv")
if(length(database)>0){
  
  indels<-read.csv(database)
  inputfile<- paste(result.folder,"FrameShift_", gsub("\\.fa.*","",gsub(".*/","", multifasta)),".xlsx",sep = "")
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

print("Thanks for using Nacho's Corona Swiss-Army-Knife Docker Image")