import PeelCommandLine

// Calls `start()` rather than `main()`, so `peel` refuses to run as root.
await PeelCommand.start()
