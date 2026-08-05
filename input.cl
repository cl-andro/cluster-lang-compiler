fn main():
    put "Initiating container namespace sandbox..."
    
    res = unshare(805437440)
    if res == 0:
        put "Namespaces unshared successfully."
        
        pid = fork()
        if pid == 0:
            put "Child process in container sandbox running!"
            chdir(c_str("/tmp"))
            put "Child changed directory to /tmp."
        else:
            put "Parent process waiting for child..."
            status = 0
            waitpid(pid, addr_of(status), 0)
            put "Child process exited. Parent resuming."
    else:
        put "Failed to unshare namespaces."
