This is a collection of scripts and tools useful when working with Actian Vector and Vector-H databases.
Each item is standalone and will provide some usage information if executed with no parameters.

#vector-minmax.sh
Script to analyse the distribution of data in a Vector min/max index. This indicates whether the data in the table is stored in sorted order for the column specified, which can be a significant performance factor if this is a join column. Disordered Min-Max indexes mean that Vector has to scan much more of the table to find blocks that satisfy the restrictions in the query's WHERE clause, and hence will result in lower performance.

#data-dist.sh
Script to examine the distribution of data within a table, to identify whether there is 'data skew' such that one
node or partition is storing more of the data than the others, due to a poor choice of distrubution key for the table relative to the data stored within it. This script reports the data in terms of rows, but you can also check the same thing in terms of disk blocks by using 'vwinfo -T <database-name>'.

#partitions.sh 
Script to calculate the correct number of partitions for a large table, based on the default of having partitions equal to half of the number of cores in a cluster. This script produces just a single number as output, with the intention that it can be used within other scripts to insert the correct number of partitions at table creation time.