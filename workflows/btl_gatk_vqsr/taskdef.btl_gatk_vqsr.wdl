workflow gatk_vqsr{
    # https://software.broadinstitute.org/gatk/documentation/article.php?id=1259
    String? onprem_download_path
    Map[String, String]? handoff_files

    call gatk_vqsr_task
}


task gatk_vqsr_task {
    String gatk_path = "/humgen/gsa-hpprojects/GATK/bin/GenomeAnalysisTK-3.7-93-ge9d8068/GenomeAnalysisTK.jar"
    File reference_tgz

    File genotype_caller_vcf

    Array[String] snp_annotation
    Array[String] indel_annotation
    Array[File] known_sites_vcfs
    Array[File] known_sites_vcf_tbis
    Array[String] snp_resource_params
    Array[String] indel_resource_params

    Int ? snp_max_gaussians
    Int ? indel_max_gaussians
    Int ? mq_cap_snp
    Int ? mq_cap_indel
    Float ts_filter_snp
    Float ts_filter_indel
    String ? extra_vr_params

    String cohort_name
    String vcf_out_fn = "${cohort_name}.vqsr.vcf"

	String debug_dump_flag
    String output_disk_gb = "100"
    String boot_disk_gb = "10"
    String ram_gb = "10"
    String cpu_cores = "1"
    String preemptible = "0"
    command {
        set -euo pipefail
        ln -sT `pwd` /opt/execution
        ln -sT `pwd`/../inputs /opt/inputs

        /opt/src/algutil/monitor_start.py
        python_cmd="
import subprocess
import os
def run(cmd):
    print (cmd)
    subprocess.check_call(cmd,shell=True)


run('echo STARTING tar xvf to unpack reference')
run('date')
run('tar xvf ${reference_tgz}')



# Drop symlink to index next to each vcf file. Leave VCFs in original directories to avoid name clashes.
# Assume that vcf and tbi list are ordered the same; downstream crash will result if not.
snp_resource_args = ''
indel_resource_args = ''
for known_sites_vcf, known_sites_vcf_tbi, snp_resource, indel_resource in zip(
    ['${sep="', '"   known_sites_vcfs }'],
    ['${sep="', '"   known_sites_vcf_tbis}'],
    ['${sep="', '"   snp_resource_params }'],
    ['${sep="', '"   indel_resource_params}']
    ):

    vcf_dir = os.path.dirname(known_sites_vcf)
    tbi_fn = os.path.basename(known_sites_vcf_tbi)
    tbi_symlink = os.path.join(vcf_dir,tbi_fn)
    if tbi_symlink != known_sites_vcf_tbi:
        print('about to: ln %s %s'%(tbi_symlink, known_sites_vcf_tbi))
        os.link(tbi_symlink, known_sites_vcf_tbi)

    snp_resource_args += '-resource:%s %s '%(snp_resource, known_sites_vcf)
    indel_resource_args += '-resource:%s %s '%(indel_resource, known_sites_vcf)


run('echo STARTING VariantRecalibrator-SNP')
run('date')

run('\
        java -Xmx8G -jar ${gatk_path} \
            -T VariantRecalibrator \
            -R ref.fasta \
            -input ${genotype_caller_vcf} \
            -mode snp \
            -recalFile snp.recal \
            -tranchesFile snp.tranches \
            %s \
            -an ${sep=" -an " snp_annotation} \
            --maxGaussians ${snp_max_gaussians} \
            --MQCapForLogitJitterTransform ${mq_cap_snp} \
            ${default="" extra_vr_params}\
            '%snp_resource_args)

run('echo STARTING ApplyRecalibration-SNP')
run('date')
run('java -Xmx8G -jar ${gatk_path} \
    -T ApplyRecalibration \
    -R ref.fasta \
    -input ${genotype_caller_vcf} \
    --ts_filter_level ${ts_filter_snp} \
    -tranchesFile snp.tranches \
    -recalFile snp.recal \
    -mode snp \
    -o snp.recalibrated.filtered.vcf \
    ')




run('echo STARTING VariantRecalibrator-INDEL')
run('date')

run('\
        java -Xmx8G -jar ${gatk_path} \
            -T VariantRecalibrator \
            -R ref.fasta \
            -input snp.recalibrated.filtered.vcf \
            -mode indel \
            -recalFile indel.recal \
            -tranchesFile indel.tranches \
            %s \
            -an ${sep=" -an " indel_annotation} \
            --maxGaussians ${indel_max_gaussians} \
            --MQCapForLogitJitterTransform ${mq_cap_indel} \
            ${default="" extra_vr_params} \
'%indel_resource_args)

run('echo STARTING ApplyRecalibration-INDEL')
run('date')
run('\
    java -Xmx8G -jar ${gatk_path} \
        -T ApplyRecalibration \
        -R ref.fasta \
        -input snp.recalibrated.filtered.vcf \
        --ts_filter_level ${ts_filter_indel} \
        -tranchesFile indel.tranches \
        -recalFile indel.recal \
        -mode indel \
        -o ${vcf_out_fn}\
')

run('echo DONE')
run('date')
"

        echo "$python_cmd"
        set +e
        python -c "$python_cmd"
        export exit_code=$?
        set -e
        echo exit code is $exit_code
        ls

        # create bundle conditional on failure of the Python section
        if [[ "${debug_dump_flag}" == "always" || ( "${debug_dump_flag}" == "onfail" && $exit_code -ne 0 ) ]]
        then
            echo "Creating debug bundle"
            # tar up the output directory
            touch debug_bundle.tar.gz
            tar cfz debug_bundle.tar.gz --exclude=debug_bundle.tar.gz .
        else
            touch debug_bundle.tar.gz
        fi
        /opt/src/algutil/monitor_stop.py

        # exit statement must be the last line in the command block
        exit $exit_code

    } output {
        File vcf_out = "${vcf_out_fn}"

        File monitor_start="monitor_start.log"
        File monitor_stop="monitor_stop.log"
        File dstat="dstat.log"
        File debug_bundle="debug_bundle.tar.gz"
    } runtime {
        docker : "gcr.io/btl-dockers/btl_gatk:1"
        memory: "${ram_gb}GB"
        cpu: "${cpu_cores}"
        disks: "local-disk ${output_disk_gb} HDD"
        bootDiskSizeGb: "${boot_disk_gb}"
        preemptible: "${preemptible}"
    }
    parameter_meta {

    }

}

