#!/usr/bin/env Rscript
#
# Script to plot age-colored PC[o]A analysis of 16S and metagenomic data
# analyzed by PhyloSift and QIIME
#

colors = rainbow(60*12, end=0.7, alpha=0.5)

library(plotrix)

color_legend <- function(x, y, xlen, ylen, main, tiks){
    text(x, y+2*ylen/3, main, adj=c(0,0), cex=0.85)
    color.legend(x, y, x+xlen, y+ylen/4, legend=tiks, rect.col=colors, cex=0.7)
}


phypro<-read.table("all.trans",sep=",")
meta <- read.table("human_micro_meta.csv",sep="\t",head=T)

ages <- trunc(1 + 12*meta$Age.of.host..years.[match(phypro$V1,as.integer(meta$MG.RAST.ID))])
logagesphy <- log(ages)
scaler <- (max(ages[!is.na(ages)])/max(logagesphy[!is.na(ages)]))
logagesphy <- logagesphy * scaler
legvec <- c(0,180,360,540,720)
legvec <- legvec / scaler
legvec <- exp(legvec)

pdf("age_pca_protein_phylosift.pdf",width=5,height=5)
plot(phypro$V2,phypro$V3,pch=16,col=colors[logagesphy+1],xlab="PC1 (59.9%)",ylab="PC2 (15.2%)", main="phylosift on marker proteins")
text(phypro$V2,phypro$V3,phypro$V1,cex=0.5)
color_legend( -6.5, 3.5, 3.5, 1.5, "age in months:", trunc(legvec)-1)
dev.off()


phy16<-read.table("16pca.trans",sep=",")
ages <- trunc(1 + 12*meta$Age.of.host..years.[match(phy16$V1,as.integer(meta$MG.RAST.ID))])
logagesphy16 <- log(ages)
logagesphy16 <- logagesphy16 * scaler


pdf("age_pca_16s_phylosift.pdf",width=5,height=5)
plot(-phy16$V2,phy16$V3,pch=16,col=colors[logagesphy16+1],xlab="PC1 ",ylab="PC2 ", main="phylosift on metagenomic 16S rRNA")
text(-phy16$V2,phy16$V3,phy16$V1,cex=0.5)
color_legend( -8, 5.5, 3.5, 1.5, "age in months:", trunc(legvec)-1)
dev.off()


pdf("age_pca_pc1pc3.pdf",width=5,height=5)
plot(phy16$V2,phy16$V4,pch=16,col=colors[logagesphy16+1],xlab="PC1 ",ylab="PC2 ")
text(phy16$V2,phy16$V4,phy16$V1, cex=0.5)
dev.off()


meta16s <- read.table("metagenome_16s_weighted_unifrac_r2.txt",header=T,sep="\t")

ll<-nrow(meta16s)-2

ages <- trunc(1 + 12*meta$Age.of.host..years.[match(meta16s$pc.vector.number,as.integer(meta$MG.RAST.ID))])
logagesqiimeta <- log(ages)
scaler <- (max(ages[!is.na(ages)])/max(logagesqiimeta[!is.na(ages)]))
logagesqiimeta <- logagesqiimeta * scaler
pdf("age_pca_meta16_pc1pc2.pdf",width=5,height=5)
plot(meta16s$X1[1:ll],meta16s$X2[1:ll],pch=16,col=colors[logagesqiimeta+1],xlab="PC1 ",ylab="PC2 ")
text(meta16s$X1[1:ll],meta16s$X2[1:ll],meta16s$pc.vector.number, cex=0.5)
color_legend( -0.45, 0.35, 0.3, 0.1, "age in months:", trunc(legvec)-1)
dev.off()

pdf("age_pca_meta16_pc1pc3.pdf",width=5,height=5)
plot(meta16s$X1[1:ll],meta16s$X3[1:ll],pch=16,col=colors[logagesqiimeta+1],xlab="PC1 ",ylab="PC3 ", main="QIIME on metagenomic 16S rRNA")
#text(meta16s$X1[1:ll],meta16s$X3[1:ll],meta16s$pc.vector.number, cex=0.5)
color_legend( 0.2, -0.4, 0.2, 0.1, "age in months:", trunc(legvec)-1)
dev.off()

pdf("age_pca_meta16_pc1pc4.pdf",width=5,height=5)
plot(meta16s$X1[1:ll],meta16s$X4[1:ll],pch=16,col=colors[logagesqiimeta+1],xlab="PC1 ",ylab="PC4 ")
text(meta16s$X1[1:ll],meta16s$X4[1:ll],meta16s$pc.vector.number, cex=0.5)
color_legend( 0.2, -0.25, 0.2, 0.1, "age in months:", trunc(legvec)-1)
dev.off()

amp16s <- read.table("amplicon_16s_weighted_unifrac_pc.txt",header=T,sep="\t")

ages <- trunc(1 + 12*meta$Age.of.host..years.[match(amp16s$pc.vector.number,meta$Metagenome)])
rastids <- meta$MG.RAST.ID[match(amp16s$pc.vector.number,meta$Metagenome)]
logages <- log(ages)
scaler <- (max(ages[!is.na(ages)])/max(logages[!is.na(ages)]))
logages <- logages * scaler
pdf("age_pca_amp16_pc1pc2.pdf",width=5,height=5)
plot(-amp16s$X1[1:ll],amp16s$X2[1:ll],pch=16,col=colors[logages+1],xlab="PC1 ",ylab="PC2 ", main="QIIME on 16S rRNA amplicons")
#text(-amp16s$X1[1:ll],amp16s$X2[1:ll],rastids[1:ll], cex=0.5)
color_legend( -0.85, 0.375, 0.5, 0.15, "age in months:", trunc(legvec)-1)
dev.off()


pdf("allofem.pdf")
par(mfrow=c(2,2))
plot(-amp16s$X1[1:ll],amp16s$X2[1:ll],pch=16,col=colors[logages+1],xlab="PC1 (50.8%)",ylab="PC2 (9.72%)", main="QIIME on 16S rRNA amplicons")
plot(-meta16s$X1[1:ll],-meta16s$X2[1:ll],pch=16,col=colors[logagesqiimeta+1],xlab="PC1 (38.9%)",ylab="PC2 (17.9%)", main="QIIME on metagenomic 16S rRNA")
plot(-phy16$V2,phy16$V3,pch=16,col=colors[logagesphy16+1],xlab="PC1 (62.2%)",ylab="PC2 (13.7%)", main="phylosift on metagenomic 16S rRNA")
plot(phypro$V2,phypro$V3,pch=16,col=colors[logagesphy+1],xlab="PC1 (59.9%)",ylab="PC2 (15.2%)", main="phylosift on metagenomic proteins")

