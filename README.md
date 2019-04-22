# wild_block_device_filler

A simple (actually somewhat complex) Perl program to fill a partition or a disk with lots of 0x00, 0xFF or alphanumerics!

Good for:

   * Speed testing (how does throughput change when writing 100 physical blocks vs 1000 physical blocks?)
   * Erasing the disk, filling it with zeros.
   * Seeing what the SSD does, and whether TRIMs did anything etc.

The `--help` option says:

    Fill a partition or a disk with meaningless data.

    --dev=<DEV>       Device file, must be given. '/dev/sdbx', 'sdbx', '/dev/sdg', 'sdg'
                      are accepted here.

    --debug           Write debugging output to stderr.

    --sync            Call fdatasync(2) after each write operation, flushing data to disk. 
                      Recommended otherwise it looks as if the program is very fast, but
                      it just fills up the memory buffers.

    --fillpat=<PAT>   Fill pattern. Currently there is:
                      > 'zero','0' for 0x00
                      > 'one','1'  for 0xFF
                      > 'alpha'    for 'ABCD...'
                      > 'moon'     for the message from Iain M. Banks' 'The Algebraist'
                      Default is: alpha

    --chunksize=<SZ>  We write "chunks", not blocks. A chunk is an array of bytes sized 
                      at several KiB, MiB or multiples of the disk's PHYSICAL BLOCK SIZE
                      (amount of data that the disk prefers to read/write in one operation,
                      e.g. 4K) or multiples of the disk's LOGICAL BLOCK SIZE (smaller or equal
                      to the physical block size, for fine-grained, but slow addressing).
                      This sets the chunk size. Format is <num><unit>, where <unit> is one of:
                      > Nothing or 'B' for Byte
                      > 'K' for KiB
                      > 'M' for MiB
                      > 'P' for physical blocks
                      > 'L' for logical blocks
                      Default is: 1024L

When you start the program (on the command line, naturally) using for example:

    wildly_fill_block_device.pl --dev=sdb1 --fillpat 0 --chunksize=1024P --sync
   
It will pointedly ask you first:

    Going on will DESTROY device /dev/sdb1 -- are you sure to continue? Type YES!!

If you decide to proceed, you will get an information scroll:

    Wrote:   2658 chunks,   1329.00 MiB, 1.09% - Overall: 73.67 MiB/s - Recent: 73.87 MiB/s - time taken: 00:00:18 - ~time remaining: 00:27:14
    Wrote:   2953 chunks,   1476.50 MiB, 1.21% - Overall: 73.68 MiB/s - Recent: 74.29 MiB/s - time taken: 00:00:20 - ~time remaining: 00:27:03
    Wrote:   3244 chunks,   1622.00 MiB, 1.33% - Overall: 73.59 MiB/s - Recent: 73.51 MiB/s - time taken: 00:00:22 - ~time remaining: 00:27:18
    Wrote:   3537 chunks,   1768.50 MiB, 1.45% - Overall: 73.54 MiB/s - Recent: 72.05 MiB/s - time taken: 00:00:24 - ~time remaining: 00:27:49
    Wrote:   3832 chunks,   1916.00 MiB, 1.57% - Overall: 73.54 MiB/s - Recent: 73.27 MiB/s - time taken: 00:00:26 - ~time remaining: 00:27:19
    Wrote:   4122 chunks,   2061.00 MiB, 1.69% - Overall: 73.45 MiB/s - Recent: 72.31 MiB/s - time taken: 00:00:28 - ~time remaining: 00:27:39
    Wrote:   4414 chunks,   2207.00 MiB, 1.81% - Overall: 73.42 MiB/s - Recent: 73.98 MiB/s - time taken: 00:00:30 - ~time remaining: 00:27:00
    Wrote:   4704 chunks,   2352.00 MiB, 1.93% - Overall: 73.36 MiB/s - Recent: 72.81 MiB/s - time taken: 00:00:32 - ~time remaining: 00:27:24
    Wrote:   4998 chunks,   2499.00 MiB, 2.05% - Overall: 73.36 MiB/s - Recent: 73.94 MiB/s - time taken: 00:00:34 - ~time remaining: 00:26:57

At the end of filling an SSD, you will see a major slowdown as reallocation stalls:

    Wrote: 244141 chunks, 122070.50 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.28 MiB/s
    Wrote: 244142 chunks, 122071.00 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.27 MiB/s
    Wrote: 244143 chunks, 122071.50 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.27 MiB/s
    Wrote: 244144 chunks, 122072.00 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.59 MiB/s - Recent throughput: 6.31 MiB/s
    Wrote: 244145 chunks, 122072.34 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.59 MiB/s - Recent throughput: 6.29 MiB/s
