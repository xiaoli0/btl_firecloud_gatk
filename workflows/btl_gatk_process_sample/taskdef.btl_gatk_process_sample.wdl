import "taskdef.btl_gatk_alignbam.wdl" as btl_gatk_alignbam
import "taskdef.btl_gatk_tcir.wdl" as btl_gatk_tcir
import "taskdef.btl_gatk_bqsr.wdl" as btl_gatk_bqsr
import "taskdef.btl_gatk_haplotypecaller.wdl" as btl_gatk_haplotypecaller


workflow gatk_process_sample {
    String? onprem_download_path
    Map[String, String]? handoff_files


    File in_bam
    String sample_name
    File reference_tgz
    Array[File] known_sites_vcfs
    Array[File] known_sites_vcf_tbis


    call btl_gatk_alignbam.gatk_alignbam_task as gatk_alignbam_task{
        input:
            in_bam = in_bam,
            sample_name = sample_name,
            reference_tgz = reference_tgz,
            output_disk_gb = "10",
            debug_dump_flag = "onfail",
    }


    call btl_gatk_tcir.gatk_tcir_task as gatk_tcir_task{
        input:
            in_bam = gatk_alignbam_task.out_bam,            
            in_bam_index = gatk_alignbam_task.out_bam_index,
            sample_name = sample_name,
            reference_tgz = reference_tgz,
            output_disk_gb = "10",
            debug_dump_flag = "onfail",

    }

    call btl_gatk_bqsr.gatk_bqsr_task as gatk_bqsr_task{
	input:
            in_bam = gatk_tcir_task.out_bam,
            in_bam_index = gatk_tcir_task.out_bam_index,
            known_sites_vcfs = known_sites_vcfs,
            known_sites_vcf_tbis = known_sites_vcf_tbis,
            sample_name = sample_name,
            reference_tgz = reference_tgz,
            output_disk_gb = "10",
            debug_dump_flag = "onfail",

	}

    call btl_gatk_haplotypecaller.gatk_haplotypecaller_task as gatk_haplotypecaller_task{
	input:
            in_bam = gatk_bqsr_task.out_bam,
            in_bam_index = gatk_bqsr_task.out_bam_index,
            bqsr_table = gatk_bqsr_task.out_bqsr_table,
            sample_name = sample_name,
            reference_tgz = reference_tgz,
            output_disk_gb = "10",
            debug_dump_flag = "onfail",

	}


    output {
        File out_gvcf = gatk_haplotypecaller_task.out_gvcf
        }

}



