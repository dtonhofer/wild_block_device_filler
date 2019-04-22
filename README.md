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

    --fillpat=<PAT>   Fill pattern currently provided:: 
                      'zero','0' for 0x00
                      'one','1'  for 0xFF
                      'alpha'    for 'ABCD...'
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

    Wrote: 715 chunks,   357.50 MiB, 0.29% - ~time remaining: 00:28:03 - Overall throughput: 72.31 MiB/s - Recent throughput: 71.42 MiB/s
    Wrote: 716 chunks,   358.00 MiB, 0.29% - ~time remaining: 00:28:03 - Overall throughput: 72.31 MiB/s - Recent throughput: 71.59 MiB/s
    Wrote: 717 chunks,   358.50 MiB, 0.29% - ~time remaining: 00:28:03 - Overall throughput: 72.32 MiB/s - Recent throughput: 71.72 MiB/s
    Wrote: 718 chunks,   359.00 MiB, 0.29% - ~time remaining: 00:28:03 - Overall throughput: 72.32 MiB/s - Recent throughput: 71.79 MiB/s
    Wrote: 719 chunks,   359.50 MiB, 0.29% - ~time remaining: 00:28:02 - Overall throughput: 72.32 MiB/s - Recent throughput: 71.82 MiB/s

At the end of filling an SSD, you will see a major slowdown as reallocation stalls:

    Wrote: 244141 chunks, 122070.50 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.28 MiB/s
    Wrote: 244142 chunks, 122071.00 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.27 MiB/s
    Wrote: 244143 chunks, 122071.50 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.60 MiB/s - Recent throughput: 6.27 MiB/s
    Wrote: 244144 chunks, 122072.00 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.59 MiB/s - Recent throughput: 6.31 MiB/s
    Wrote: 244145 chunks, 122072.34 MiB, 100.00% - ~time remaining: 00:00:00 - Overall throughput: 64.59 MiB/s - Recent throughput: 6.29 MiB/s
