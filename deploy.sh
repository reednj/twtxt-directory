#!/bin/sh

WEB=~/twtxt.reednj.com
SRC=~/code/twtxt.git
CONFIG=~/code/config_backup/twtxt

# update the data
mkdir -p $SRC/data
mkdir -p $WEB/data
cp $WEB/data/* $SRC/data

# update the data
cp $WEB/public/twtxt/*.txt $SRC/public/twtxt

# copy the required files to the website
rm -rf $WEB/*
cp -R $SRC/* $WEB
cp $SRC/.ruby-version $WEB
cp $CONFIG/* $WEB/config/

cd $WEB/
rake app:installed:build

echo "Website deployed"

