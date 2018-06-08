FROM ubuntu:xenial

MAINTAINER vventirozos@omniti.com

### CHANGE THE FOLLOWING 3 PARAMETERS IF YOU WANNA CHANGE USER, POSTGRES INSTALL AND PGDATA DIRECTORIES ###

ENV PGUSER=postgres
ENV PGBINDIR=/home/$PGUSER/pgsql
ENV PGDATADIR=/home/$PGUSER/pgdata

#Installing packages and creating a OS user

RUN apt-get update && \
apt-get install -y \
	sudo wget apt-transport-https joe less build-essential \
	libreadline-dev zlib1g-dev flex bison libxml2-dev \
	libxslt-dev libssl-dev screen git unzip cpanminus && \
	useradd -c /home/$PGUSER -ms /bin/bash $PGUSER

#add user postgres to sudoers - SECURITY WARNING

run echo "$PGUSER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

run cpanm TAP::Parser::SourceHandler::pgTAP

# The next steps will run as postgres

USER $PGUSER
WORKDIR /home/$PGUSER
#getting the -latest- (ALWAYS) postgres version compile world and install

RUN wget https://www.postgresql.org/ftp/latest/ -q -O - |grep "tar.gz" |grep -v md5 |grep -v sha256 |awk -F "\"" '{print $2}' |xargs wget && \
	ls -1 *.tar.gz |xargs tar zxfv && \
	cd postgres* ; ./configure --prefix=$PGBINDIR ; make world ; make install-world

### Downloading pg_jobmon
RUN git clone https://github.com/omniti-labs/pg_jobmon/
RUN export PATH=$PATH:$PGBINDIR/bin && cd /home/$PGUSER/pg_jobmon/ && make && make install
RUN wget -c http://api.pgxn.org/dist/pgtap/0.98.0/pgtap-0.98.0.zip
RUN unzip pgtap-*
RUN export PATH=$PATH:$PGBINDIR/bin && cd pgtap-0.98.0 && make && make install

# PGDATA creation and initdb -WITH- data checksums

RUN mkdir $PGDATADIR && \
	$PGBINDIR/bin/initdb -k -D $PGDATADIR

# setting some postgres configurables

RUN echo "listen_addresses = '*'" >> $PGDATADIR/postgresql.conf && \
	echo "port = 5432" >> $PGDATADIR/postgresql.conf 

## Setting pg_hba.conf for passwordless access for all users and replication -- SECURITY WARNING

#install some extensions , create a replication user and a monkey database

RUN $PGBINDIR/bin/pg_ctl -D $PGDATADIR/ start ; sleep 10 && \
	$PGBINDIR/bin/psql -c "create extension dblink;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pgtap;" template1 && \
	$PGBINDIR/bin/psql -c "create extension postgres_fdw;" template1 && \
	$PGBINDIR/bin/createdb monkey && \
	$PGBINDIR/bin/psql -c "CREATE SCHEMA jobmon;" monkey && \
	$PGBINDIR/bin/psql -c "CREATE extension pg_jobmon schema jobmon;" monkey && \
	$PGBINDIR/bin/psql -c "insert into jobmon.dblink_mapping_jobmon (username,port) values ('postgres','5432');" monkey && \
	$PGBINDIR/bin/pg_ctl -D $PGDATADIR/ -m fast stop

RUN echo "#!/bin/bash" > /home/$PGUSER/test_jobmon.sh && \
	echo "/home/$PGUSER/pgsql/bin/pg_ctl -D $PGDATADIR start" >>/home/$PGUSER/test_jobmon.sh && \
	echo "sleep 3" >>/home/$PGUSER/test_jobmon.sh && \
	echo "/usr/local/bin/pg_prove -b /home/$PGUSER/pgsql/bin/psql -f -v /home/postgres/pg_jobmon/test/test0* -d monkey" >>/home/$PGUSER/test_jobmon.sh && \
	chmod +x /home/$PGUSER/test_jobmon.sh

#USER root
CMD sudo service ssh restart && $PGBINDIR/bin/pg_ctl -D $PGDATADIR start && sleep 1  && tail -f /home/$PGUSER/pgdata/log/*.log
#Tadah !
