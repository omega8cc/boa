// This program dumps the content of a shared memory block
// used by Linux/Cdorked.A into a file named httpd_cdorked_config.bin
// when the machine is infected.
//
// Some of the data is encrypted. If your server is infected and you
// would like to help, please send the httpd_cdorked_config.bin
// and your httpd executable to our lab for analysis. Thanks!
//
// Build with gcc -o dump_cdorked_config dump_cdorked_config.c
//
// Marc-Etienne M.Léveillé <leveille@eset.com>
//

#include <stdio.h>
#include <sys/shm.h>

#define CDORKED_SHM_SIZE (6118512)
#define CDORKED_OUTFILE "httpd_cdorked_config.bin"

int main (int argc, char *argv[]) {
    int maxkey, id, shmid, infected = 0;
    struct shm_info shm_info;
    struct shmid_ds shmds;
    void * cdorked_data;
    FILE * outfile;
    
    maxkey = shmctl(0, SHM_INFO, (void *) &shm_info);
    for(id = 0; id <= maxkey; id++) {
        shmid = shmctl(id, SHM_STAT, &shmds);
        if (shmid < 0)
            continue;
        
        if(shmds.shm_segsz == CDORKED_SHM_SIZE) {
            // We have a matching Cdorked memory segment
            infected++;
            printf("A shared memory matching Cdorked signature was found.\n");
            printf("You should check your HTTP server's executable file integrity.\n");
            
            cdorked_data = shmat(shmid, NULL, 0666);
            if(cdorked_data != NULL) {
                outfile = fopen(CDORKED_OUTFILE, "wb");
                if(outfile == NULL) {
                    printf("Could not open file %s for writing.", CDORKED_OUTFILE);
                }
                else {
                    fwrite(cdorked_data, CDORKED_SHM_SIZE, 1, outfile);
                    fclose(outfile);
                    
                    printf("The Cdorked configuration was dumped in the %s file.\n\n", CDORKED_OUTFILE);
                }
            }
        }
    }
    if(infected == 0) {
        printf("No shared memory matching Cdorked signature was found.\n");
        printf("To further verify your server, run \"ipcs -m -p\" and look");
        printf(" for a memory segments created by your http server.\n");
    }
    else {
        printf("If you would like to help us in our research on Cdorked, ");
        printf("please send the httpd_cdorked_config.bin and your httpd executable file ");
        printf("to our lab for analysis at leveille@eset.com. Thanks!\n");
    }
    return infected;
}
