pg_jobmon
=========

pg_jobmon is an extension to add the capability to log the progress of running functions and provide a limited monitoring capability to those logged functions. 
The logging is done in a NON-TRANSACTIONAL method, so that if your function fails for any reason, all steps up to that point are kept in the log tables. The logging portions of the extension should be stable and ready for production use. The monitoring capability is still fairly new and may require adjusting but it should be usable.
A blog post giving more extensive examples can be found at http://keithf4.com (coming soon)

INSTALLATION
------------

Requirements: dblink extension
Copy the pg_jobmon.control and pg_jobmon--<version>.sql files to your $BASEDIR/share/extension folder. Create schema (not required but recommended) and then install using the PostgreSQL extensions system

    CREATE SCHEMA jobmon;
    CREATE EXTENSION pg_jobmon SCHEMA jobmon;


UPGRADE
-------

Make sure all the upgrade scripts for the version you have installed up to the most recent version are in the $BASEDIR/share/extension folder. 

    ALTER EXTENSION pg_jobmon UPDATE TO '<latest version>';

Please note that until this extension is officially announced and put into the OmniTI github repository, there may not be upgrade scripts available.


AUTHOR
------

Keith Fiske
OmniTI, Inc - http://www.omniti.com
keith@omniti.com


LICENSE AND COPYRIGHT
---------------------

PGExtractor is released under the PostgreSQL License, a liberal Open Source license, similar to the BSD or MIT licenses.

Copyright (c) 2012 OmniTI, Inc.

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
