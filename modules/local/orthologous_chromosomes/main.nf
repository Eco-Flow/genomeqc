process ORTHOLOGOUS_CHROMOSOMES {
    tag "orthologous_chromosomes"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "community.wave.seqera.io/library/python_pip_pandas:2fd05a70c67560f2"

    input:
    path orthogroups_tsv
    path gff_files

    output:
    path "species_orthologous_chromosomes.tsv", emit: species_summary
    path "pairwise_chromosome_orthology.tsv", emit: pairwise_summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/bin/bash

    python3 << 'EOF'
import os
import sys
from collections import defaultdict

# Install and import pandas
try:
    import pandas as pd
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "pandas"])
    import pandas as pd

print("[INFO] Starting chromosome orthology summary script...")
print("[INFO] Checking current directory files:")
print(os.listdir("."))

# Check that the expected files exist
orthogroups_file = "${orthogroups_tsv}"
if not os.path.exists(orthogroups_file):
    print(f"[ERROR] {orthogroups_file} not found")
    sys.exit(1)

# Get GFF files from input
gff_files = []
for item in "${gff_files}".split():
    if os.path.exists(item) and item.endswith(".gff"):
        gff_files.append(item)

if not gff_files:
    print("[ERROR] No GFF files found in the input")
    sys.exit(1)

print(f"[INFO] Found {len(gff_files)} GFF files:")
for f in gff_files:
    print(f" - {f}")

# Load the actual Orthogroups.tsv file
try:
    orthogroups_df = pd.read_csv(orthogroups_file, sep='\\t')
    print(f"[INFO] Loaded {len(orthogroups_df)} orthogroups")
    print(f"[INFO] Columns: {list(orthogroups_df.columns)}")
except Exception as e:
    print(f"[ERROR] Failed to load {orthogroups_file}: {e}")
    sys.exit(1)

# Parse GFF files to create gene to chromosome mapping
gene_to_chr = {}
for gff_file in gff_files:
    species_name = os.path.basename(gff_file).replace(".gff", "").replace(".longest", "")
    print(f"[INFO] Processing {gff_file} for species {species_name}")
    
    try:
        with open(gff_file, 'r') as f:
            for line in f:
                if line.startswith('#'):
                    continue
                parts = line.strip().split('\\t')
                if len(parts) >= 9 and parts[2] == 'mRNA':
                    chromosome = parts[0]
                    attributes = parts[8]
                    
                    # Extract gene ID from attributes - try multiple patterns
                    gene_id = None
                    for attr in attributes.split(';'):
                        attr = attr.strip()
                        if attr.startswith('ID='):
                            gene_id = attr.split('=')[1]
                            break
                        elif attr.startswith('Name='):
                            gene_id = attr.split('=')[1]
                            break
                    
                    if gene_id:
                        gene_to_chr[gene_id] = (species_name, chromosome)
    except Exception as e:
        print(f"[WARNING] Error processing {gff_file}: {e}")

print(f"[INFO] Mapped {len(gene_to_chr)} genes to chromosomes")

# Debug: Show some gene mappings
if gene_to_chr:
    print("[INFO] Sample gene mappings:")
    for i, (gene, (sp, chr)) in enumerate(gene_to_chr.items()):
        if i < 5:  # Show first 5
            print(f"  {gene} -> {sp}:{chr}")

# Track orthologous chromosome pairs
orthologous_chr_pairs = defaultdict(int)
species_chr_syntenic = defaultdict(set)

processed_orthogroups = 0
for _, row in orthogroups_df.iterrows():
    gene_chroms = defaultdict(set)
    
    for species, genes in row.items():
        if species == "Orthogroup":
            continue
        
        if pd.isna(genes) or str(genes).strip() == "":
            continue
            
        for gene in str(genes).split(","):
            gene = gene.strip()
            if gene in gene_to_chr:
                sp, chrom = gene_to_chr[gene]
                gene_chroms[sp].add(chrom)
    
    # Get all species pairs and update orthologous chromosome counts
    species_list = list(gene_chroms.keys())
    if len(species_list) >= 2:
        processed_orthogroups += 1
        for i in range(len(species_list)):
            for j in range(i+1, len(species_list)):
                sp1, sp2 = species_list[i], species_list[j]
                for chr1 in gene_chroms[sp1]:
                    for chr2 in gene_chroms[sp2]:
                        key = tuple(sorted([ (sp1, chr1), (sp2, chr2) ]))
                        orthologous_chr_pairs[key] += 1
                        species_chr_syntenic[sp1].add(chr1)
                        species_chr_syntenic[sp2].add(chr2)

print(f"[INFO] Processed {processed_orthogroups} orthogroups with multi-species genes")

# Create output DataFrames
if orthologous_chr_pairs:
    pairwise_output = pd.DataFrame([
        {"Species1": k[0][0], "Chr1": k[0][1], "Species2": k[1][0], "Chr2": k[1][1], "Orthogroup_Count": v}
        for k, v in orthologous_chr_pairs.items()
    ])
else:
    # Create empty DataFrame with correct columns
    pairwise_output = pd.DataFrame(columns=["Species1", "Chr1", "Species2", "Chr2", "Orthogroup_Count"])

if species_chr_syntenic:
    species_chr_count = pd.DataFrame([
        {"Species": sp, "Syntenic_Chromosomes": len(chrs)}
        for sp, chrs in species_chr_syntenic.items()
    ])
else:
    # Create empty DataFrame with correct columns
    species_chr_count = pd.DataFrame(columns=["Species", "Syntenic_Chromosomes"])

# Save results
pairwise_output.to_csv("pairwise_chromosome_orthology.tsv", sep='\\t', index=False)
species_chr_count.to_csv("species_orthologous_chromosomes.tsv", sep='\\t', index=False)

print("\\n[INFO] Results saved:")
print("- pairwise_chromosome_orthology.tsv")
print("- species_orthologous_chromosomes.tsv")

print("\\n[INFO] Pairwise chromosome orthology summary:")
print(pairwise_output.head())

print("\\n[INFO] Species orthologous chromosome counts:")
print(species_chr_count)
EOF

    cat <<-END_VERSIONS > versions.yml
"ECOFLOW_GENOMEQC:GENOMEQC:GENOME_AND_ANNOTATION:ORTHOLOGOUS_CHROMOSOMES":
    python: \$(python --version | sed 's/Python //g')
    pandas: \$(python -c "import pandas; print(pandas.__version__)")
END_VERSIONS
    """
}