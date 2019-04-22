# wild_block_device_filler

A simple (actually somewhat complex) perl program to fill a partition with 0x00, 0xFF or alphanumerics

Good for speed testing, erasing or seeing what the SSD does.

The help says:

    Fill a partition or a disk with meaningless data.

    --dev=<DEV>       Device file, must be given. '/dev/sdbx' or 'sdbx' are accepted here.
    --debug           Write debugging output to stderr.
    --sync            Call fdatasync(2) after each write operation, flushing data to disk. Recommended!
    --fillpat=<PAT>   Fill pattern: 'zero|0' for 0x00, 'one|1' for 0xFF, 'alpha' for 'ABCD...'. Default: alpha.
    --chunksize=<SZ>  We write chunks. This sets the chunk size. Format is <num><unit>, where <unit> is one of:
                      Nothing or 'B' for Byte, 'K' for KiB, 'M' for MiB, 'P' for physical blocks, 'L' for logical blocks.
                      Default is: 1024L.
