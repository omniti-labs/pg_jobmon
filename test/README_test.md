PG Jobmon Test Suite
====================

The pgTAP testing suite is used to provide functional testing during development and evaluation. Please see the pgTAP home page for more details on its installation and use.

http://pgTAP.org

Since pg_jobmon uses dblink, testing cannot be done as recommended in the pgTAP documenation by putting everything into transactions that can be rolled back. The tests have been split into different logical groups in their own files and MUST be run in numerical order. They assume that the required extensions have been installed in the following schemas:

    dblink: dblink
    pg_jobmon: jobmon 
    pgTAP: tap

If you've installed any of the above extensions in a different schema and would like to run the test suite, simply change the configuration option found at the top of each testing file to match your setup.

    SELECT set_config('search_path','jobmon, dblink, tap',false);

Once that's done, it's best to use the **pg_prove** script that pgTAP comes with to run all the tests. I like using the -f -o -v options to get more useful feedback. Note that only the numbered tests use pgTAP. So to run them all at once, you can use this command and avoid running the other tests

pg_prove -f -v /path/to/pg_jobmon/test/test0*

Not all of pg_jobmon's functions can be tested with pgTAP due to requiring multiple sessions that wait on others. See the instructions contained in each of the other test files, and follow the on screen prompts when run, for how they work: 

test_cancel_job.sql
test_running_job.sql
test_blocked_job.sql (depends on test_blocked_job_blocker.sql being run first)

The tests are not required to run pg_jobmon, so if you don't feel safe doing this you don't need to run the tests. But if you are running into problems and report any issues without a clear explanation of what is wrong, I will ask that you run the test suite so you can try and narrow down where the problem may be. You are free to look through to tests to see exactly what they're doing. The final numbered test script can be run on its own and should clean up everything and leave your database as it was before.
