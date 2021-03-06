#!/usr/bin/env Rscript

fpd<-read.table("all_fpd",sep=",",head=T)
abab<-read.table("human_micro_meta.csv",head=T,sep="\t")

logage<-log(12*abab$Age.of.host..years.[match(fpd$placerun,as.integer(abab$MG.RAST.ID))])

pdf("phylo_diversity.pdf")
par(mar=c(5.1,4.1,4.1,4.1))
plot(logage,fpd$awpd,pch=3,ylim=c(0.25,3.5),ylab="Abundance weighted phylogenetic diversity",xlab="Age in months (log scale)",axes=F)
points(logage,fpd$pd/50,col=2)
abline(line(logage,fpd$pd/50),col=2)
abline(line(logage,fpd$awpd))
pdaxis=c(0,0.5,1,1.5,2,2.5,3)
axis(side=2,at=pdaxis,labels=pdaxis)
ageaxis=seq(0,6,by=1)
axis(side=1,at=ageaxis,labels=round(signif(exp(ageaxis),2)))
axis(side=4,at=pdaxis,labels=50*pdaxis)
mtext("Unweighted phylogenetic diversity (AA subs. per site)",side=4,line=2.5)
legend("topleft", legend=c("Unweighted PD", "Abundance weighted PD"), pch=c(1,3),col=c(2,1))
box()
dev.off()

