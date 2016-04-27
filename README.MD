This is a collection of scripts and tools useful when working with Actian Vector and Vector-H databases.
Each item is standalone and will provide some usage information if executed with no parameters.

#vector-minmax.sh
Script to analyse the distribution of data in a Vector min/max index. This indicates whether the data in the table is stored in sorted order for the column specified, which can be a significant performance factor if this is a join column. Disordered Min-Max indexes mean that Vector has to scan much more of the table to find blocks that satisfy the restrictions in the query's WHERE clause, and hence will result in lower performance.

#data-dist.sh
Script to examine the distribution of data within a table, to identify whether there is 'data skew' such that one node or partition is storing more of the data than the others, due to a poor choice of distrubution key for the table relative to the data stored within it. 

This script reports the data in terms of rows, but you can also check the same thing in terms of disk blocks by using `vwinfo -T <database-name>`.

#partitions.sh 
Script to calculate the correct number of partitions for a large table, based on the default of having partitions equal to half of the number of cores in a cluster. This script produces just a single number as output, with the intention that it can be used within other scripts to insert the correct number of partitions at table creation time.

#runall.sh
Script to take a collection of .sql scripts and execute all of these against a target database to test performance. Script takes a few parameters to control the total number of queries executed, and the number of queries that are executed in parallel. For example, if you ask for 150 queries total and 30 in parallel, and supply a folder with 10 .sql files in it, then each of the 10 .sql files will be executed 15 times (serially, in alphabetical order). before starting a new .sql file, the script counts the number of currently executing scripts (by counting `sql` processes via `ps`) and only starts a new one when the number of executions drops below the target concurrency level. Further parameters allow for capturing profiles for every query.
```
    Usage:
          -d|--database      {DB Name}
          -g|--profgraph     {Y|N to create x100 profile graphs}
          -i|--iisystem      {II_SYSTEM}
          -k|--keeplog       {Y|N to keep temporary files}
          -m|--maxconcurrent {Max number of concurrent queries}
          -n|--numruns       {Number of runs}
          -p|--profiledata   {Y|N to generate profile data from system catalogs}
          -s|--scriptdir     {Script Directory Name}
```
Example: `./runall.sh -d testdb -g N -i $II_SYSTEM -k Y -m 15 -n 150 -p N -s /mnt/vh/projects/testing/new-scripts`

#monitor-vwinfo.sh
Script that is intended to be run regularly via cron to gather a snapshot of the memory usage information of Vector or VectorH over a period of days or weeks. This data should be appended to the same log file every time it runs.

There is then a matching utility, `vwinfo-pivot.awk`, that is intended to parse the raw vwinfo log data and transform it into a CSV structure that can then be easily loaded into your favourite graphing or analysis tool. Excel, Apache Zeppelin, and Jupyter Notebook all work well for this sort of thing.