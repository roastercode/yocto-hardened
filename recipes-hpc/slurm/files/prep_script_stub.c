/*
 * Stub prep_script plugin for cross-compiled Slurm.
 * send_slurmd_conf_lite is only available in slurmd binary,
 * not in libslurm — this stub avoids the dlopen failure.
 */
#include <slurm/slurm.h>

const char plugin_name[] = "prep script plugin";
const char plugin_type[] = "prep/script";
const uint32_t plugin_version = SLURM_VERSION_NUMBER;

int init(void) { return SLURM_SUCCESS; }
void fini(void) {}

int prep_p_prolog(job_env_t *job_env, slurm_cred_t *cred) { return SLURM_SUCCESS; }
int prep_p_epilog(job_env_t *job_env, slurm_cred_t *cred) { return SLURM_SUCCESS; }
int prep_p_prolog_slurmctld(job_record_t *job_ptr, bool *async) { return SLURM_SUCCESS; }
int prep_p_epilog_slurmctld(job_record_t *job_ptr, bool *async) { return SLURM_SUCCESS; }
