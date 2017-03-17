#!/bin/bash

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

# load chruby
source /usr/local/share/chruby/chruby.sh
source /usr/local/share/chruby/auto.sh

cd $WEB/
bundle install
rake app:installed:build

echo "Website deployed"

