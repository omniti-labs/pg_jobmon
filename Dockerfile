FROM ubuntu:xenial

MAINTAINER vventirozos@omniti.com

### CHANGE THE FOLLOWING 3 PARAMETERS IF YOU WANNA CHANGE USER, POSTGRES INSTALL AND PGDATA DIRECTORIES ###

ENV PGUSER=postgres
ENV PGBINDIR=/home/$PGUSER/pgsql
ENV PGDATADIR=/home/$PGUSER/pgdata

#Installing packages and creating a OS user

RUN apt-get update && apt-get install -y sudo wget apt-transport-https joe less build-essential libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev libssl-dev openssh-server screen git unzip cpanminus && \
	useradd -c /home/$PGUSER -ms /bin/bash $PGUSER

RUN echo "deb [trusted=yes] https://repo.iovisor.org/apt/xenial xenial-nightly main" | sudo tee /etc/apt/sources.list.d/iovisor.list

RUN apt-get update && apt-get install -y bcc-tools

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
# Downloading OmniPITR
RUN git clone https://github.com/omniti-labs/omnipitr -b OmniPITRv2
### Downloading pg_jobmon
RUN git clone https://github.com/omniti-labs/pg_jobmon/
RUN export PATH=$PATH:$PGBINDIR/bin && cd /home/$PGUSER/pg_jobmon/ && make && make install
RUN wget -c http://api.pgxn.org/dist/pgtap/0.98.0/pgtap-0.98.0.zip
RUN unzip pgtap-*
RUN export PATH=$PATH:$PGBINDIR/bin && cd pgtap-0.98.0 && make && make install

#setting up a decent working env

RUN echo "export PGDATA=$PGDATADIR" >> ~/.bashrc && \
	echo "export PATH=$PATH:$PGBINDIR/bin" >> ~/.bashrc && \
	echo "LD_LIBRARY_PATH=$PGBINDIR/lib">> ~/.bashrc && \
	echo "alias joe='joe -wordwrap -nobackups -tab 2'"  >> ~/.bashrc
## No hate for joe, just love !

# PGDATA creation and initdb -WITH- data checksums

RUN mkdir $PGDATADIR && \
	mkdir /home/$PGUSER/wal_archive && \
	mkdir -p /home/$PGUSER/omnipitr_data/state && \
	mkdir -p /home/$PGUSER/omnipitr_data/tmp && \
	$PGBINDIR/bin/initdb -k -D $PGDATADIR

# setting some postgres configurables

RUN echo "listen_addresses = '*'" >> $PGDATADIR/postgresql.conf && \
	echo "port = 5432" >> $PGDATADIR/postgresql.conf && \
	echo "wal_level = logical" >> $PGDATADIR/postgresql.conf && \
	echo "checkpoint_completion_target = 0.9" >> $PGDATADIR/postgresql.conf && \
	echo "archive_mode = on" >> $PGDATADIR/postgresql.conf && \
	echo "archive_command = '/bin/true'" >> $PGDATADIR/postgresql.conf && \
	echo "#OPTIONAL ARCHIVE_COMMAND FOR OMNIPITR" >> $PGDATADIR/postgresql.conf && \
	echo "#archive_command = '/home/$PGUSER/omnipitr/bin/omnipitr-archive -D $PGDATADIR -l $PGDATADIR/pg_log/archive-^Y-^m-^d.log -s /home/$PGUSER/omnipitr_data/state -db /home/$PGUSER/omnipitr_data/backup -dr gzip=rsync://10.0.0.3/wal_archive -t /home/$PGUSER/omnipitr_data/omnipitr/tmp -v \"%p\"'" >> $PGDATADIR/postgresql.conf && \
	echo "max_wal_senders = 16" >> $PGDATADIR/postgresql.conf && \
	echo "wal_keep_segments = 10" >> $PGDATADIR/postgresql.conf && \
	echo "max_replication_slots = 10" >> $PGDATADIR/postgresql.conf && \
	echo "hot_standby = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_destination = 'stderr'" >> $PGDATADIR/postgresql.conf && \
	echo "logging_collector = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_filename = 'postgresql-%Y-%m-%d.log'" >> $PGDATADIR/postgresql.conf && \
	echo "wal_log_hints = on" >> $PGDATADIR/postgresql.conf && \
	echo "log_line_prefix = '%t:%p:%u:[%i] '" >> $PGDATADIR/postgresql.conf

## Setting pg_hba.conf for passwordless access for all users and replication -- SECURITY WARNING

RUN echo "host    all             all             10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf && \
	echo "host    replication     repuser         10.0.0.1/16            trust" >> $PGDATADIR/pg_hba.conf

#exposing ports
EXPOSE 5432
EXPOSE 22


#install some extensions , create a replication user and a monkey database

RUN $PGBINDIR/bin/pg_ctl -D $PGDATADIR/ start ; sleep 10 && \
	$PGBINDIR/bin/psql -c "create extension pg_buffercache ;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pageinspect;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pg_prewarm;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pg_stat_statements;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pgstattuple;" template1 && \
	$PGBINDIR/bin/psql -c "create extension dblink;" template1 && \
	#$PGBINDIR/bin/psql -c "create extension pg_jobmon;" template1 && \
	$PGBINDIR/bin/psql -c "create extension pgtap;" template1 && \
	$PGBINDIR/bin/psql -c "create extension postgres_fdw;" template1 && \
	$PGBINDIR/bin/psql -c "create user repuser with replication;" template1 && \
	$PGBINDIR/bin/createdb monkey && \
	$PGBINDIR/bin/psql -c "CREATE SCHEMA jobmon;" monkey && \
	$PGBINDIR/bin/psql -c "CREATE extension pg_jobmon schema jobmon;" monkey && \
	$PGBINDIR/bin/psql -c "insert into jobmon.dblink_mapping_jobmon (username,port) values ('postgres','5432');" monkey && \
	$PGBINDIR/bin/pg_ctl -D $PGDATADIR/ -m fast stop

#Set a recovery.done so the slaves can find it

RUN echo "standby_mode = 'on' " >$PGDATADIR/recovery.done && \
	echo "primary_conninfo = 'user=repuser host=10.0.0.2 port=5432 application_name=a_slave'" >>$PGDATADIR/recovery.done && \
	echo "#restore_command = '/home/$PGUSER/omnipitr/bin/omnipitr-restore -l $PGDATADIR/pg_log/restore-^Y-^m-^d.log -s gzip=/home/$PGUSER/wal_archive/ -f $PGDATADIR/finish.recovery -p $PGDATADIR/pause.removal -t /home/$PGUSER/omnipitr_data/omnipitr/tmp -ep hang -r %r -rb -sr -v %f %p'" >>$PGDATADIR/recovery.done && \
	echo "#archive_cleanup_command = '/home/$PGUSER/omnipitr/bin/omnipitr-cleanup -l /$PGDATADIR/pg_log/cleanup-^Y-^m-^d.log -a gzip=/home/$PGUSER/wal_archive/ -p $PGDATADIR/pause.removal %r'" >>$PGDATADIR/recovery.done && \
	echo "trigger_file = '$PGDATADIR/finish.recovery'" >>$PGDATADIR/recovery.done && \
	echo "recovery_target_timeline = 'latest'" >>$PGDATADIR/recovery.done

RUN echo "#!/bin/bash" > /home/$PGUSER/test_jobmon.sh && \
	echo "/home/$PGUSER/pgsql/bin/pg_ctl -D $PGDATADIR start" >>/home/$PGUSER/test_jobmon.sh && \
	echo "sleep 3" >>/home/$PGUSER/test_jobmon.sh && \
	echo "/usr/local/bin/pg_prove -b /home/$PGUSER/pgsql/bin/psql -f -v /home/postgres/pg_jobmon/test/test0* -d monkey" >>/home/$PGUSER/test_jobmon.sh && chmod +x /home/$PGUSER/test_jobmon.sh

#USER root
CMD sudo service ssh restart && $PGBINDIR/bin/pg_ctl -D $PGDATADIR start && sleep 1  && tail -f /home/$PGUSER/pgdata/log/*.log
#Tadah !
