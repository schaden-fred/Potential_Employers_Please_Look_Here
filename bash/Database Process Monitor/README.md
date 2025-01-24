# Feed Monitor
This is a generic bash script for monitoring the status of an inbound datafeed that interacts with a PostgreSQL database.  It should be run as a Cron job at regular intervals.  

On each run, it will check the database for signs that the process has failed.  (No new messages, or messages backing up in the queue and not being processed)
If it detects a failure, it will kill and restart the process, and set a flag to indicate that it has done this.
On the next run, if it still detects a failure, it will send an HTTP push to your monitoring system (Uptime Kuma in this example) which can then trigger an on-call alert.

# How could this be improved?
This was written in any free time I had at work, to address a specific set of failure modes that we were seeing on a data feed.  Because of this, the code follows my stream of consciousness.  It works, but it's repetitive and not as easy to read as it could be.

To improve it, I'd break the code down into a the following sections.
1. Populate variables from ENV and from Postgres database.
2. Define an array variable containing error check queries, error codes, plain English error messages, steps to recover, and any other values needed for each potential error type.
3. Define a function to query for each error condition, using the data in the array variable.  If any error condition is active, return a code for that error condition.
4. Define a function to try and resolve the error, using the data in the array variable.
5. Define a function to alert based on the returned code.  Alert behavior will vary depending on whether the system is Production or not.
6. Use a FOR or WHILE loop to run each query, attempt to resolve if needed, and alert if needed.  Exit the loop once any single error condition has been detected and acted upon.