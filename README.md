pg_jobmon
=========

pg_jobmon is an extension to add the capability to log the progress of running functions and provide a limited monitoring capability to those logged functions. The logging is done in a NON-TRANSACTIONAL method, so that if your function fails for any reason, all steps up to that point are kept in the log tables. 
See the pg_jobmon.md file in docs for more details. Also see my blog for some examples and tips: http://keithf4.com/pg_jobmon

INSTALLATION
------------

Requirements: dblink extension

In directory where you downloaded pg_jobmon to run

    make
    make install

Log into PostgreSQL and run the following commands. Schema can be whatever you wish, but it cannot be changed after installation.

    CREATE SCHEMA jobmon;
    CREATE EXTENSION pg_jobmon SCHEMA jobmon;

This extension uses dblink to connect back to the same database that pg_jobmon is running on (this is how the non-transactional magic is done). To allow non-superusers to use dblink, you'll need to enter role credentials into the dblink_mapping table that pg_jobmon installs.
    
    INSERT INTO jobmon.dblink_mapping (username, pwd) VALUES ('rolename', 'rolepassword');

Ensure you add the relevant line to the pg_hba.conf file for this role. It will be connecting back to the same postgres database locally.
    
    # TYPE  DATABASE       USER            ADDRESS                 METHOD
    local   dbname         rolename                                md5

The following permissions should be given to the above role (substitude relevant schema names as appropriate):
    
    grant usage on schema jobmon to rolename;
    grant usage on schema dblink to rolename;
    grant select, insert, update, delete on all tables in schema jobmon to rolename;
    grant execute on all functions in schema jobmon to rolename;
    grant all on all sequences in schema jobmon to rolename;

If you're running PostgreSQL on a port other than the default (5432), you can also use the dblink_mapping table to change the port that dblink will uses.

    INSERT INTO jobmon.dblink_mapping (port) VALUES ('5999');

Be aware that the dblink_mapping table can only have a single row, so if you're using a custom role and different port, all can just be entered in the same row. None of the columns is required, so just use the ones you need for your setup.

    INSERT INTO jobmon.dblink_mapping (username, pwd, port) VALUES ('rolename', 'rolepassword', '5999');

UPGRADE
-------

Make sure all the upgrade scripts for the version you have installed up to the most recent version are in the $BASEDIR/share/extension folder. 

    ALTER EXTENSION pg_jobmon UPDATE TO '<latest version>';

For detailed change logs of each version, please see the top of each update script.

AUTHOR
------

Keith Fiske
OmniTI, Inc - http://www.omniti.com
keith@omniti.com


LICENSE AND COPYRIGHT
---------------------

pg_jobmon is released under the PostgreSQL License, a liberal Open Source license, similar to the BSD or MIT licenses.

Copyright (c) 2013 OmniTI, Inc.

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
