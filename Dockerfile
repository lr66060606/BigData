# ============================================================================
# Base Image: Debian Bookworm (Slim)
# Purpose: Base runtime environment for all Labs & Lectures
# Course: Big Data Analysis in TJU-UOL-Fuzhou Joint College
# ============================================================================
FROM debian:bookworm-slim

LABEL maintainer="TJU-UOL-Fuzhou Joint College" \
      course="Big Data Analysis (BDA)" \
      semester="2026/27-Fall" \
      description="Full environment for ALL 5 intensive labs (Lab1-5) covering R Fundamentals, Sparklyr, Knowledge Graphs, Neo4j, and Bayesian Networks." \
      labs_covered="Lab1, Lab2, Lab3, Lab4, Lab5" \
      contact="gongxj@tju.edu.cn"

# ============================================================================
# Global Environment Variables
# ============================================================================
# Disable interactive prompts during installation (e.g., timezone selection)
# to prevent the build from hanging.
ENV DEBIAN_FRONTEND=noninteractive

# Set R package repository (Tsinghua mirror, very fast for builds in China).
ENV CRAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/CRAN

# Set UTF-8 locale to avoid R warnings and support Chinese characters.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LANGUAGE=C.UTF-8

# ============================================================================
# Layer 1: Base System Dependencies (apt)
# Description: Underlying libraries required to run R, RStudio Server, Spark,
#              and to compile R packages.
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # ------------------------------------------------------------------------
    # R Language Core
    # Corresponding Lab: RStudio setup, R basics, data frame operations,
    #                    Bayesian network modeling.
    # Rationale: Fundamental prerequisite for executing any R code.
    # ------------------------------------------------------------------------
    r-base r-base-dev \
    # ------------------------------------------------------------------------
    # Java Runtime Environment (OpenJDK 17)
    # Corresponding Lab: Spark in R (sparklyr)
    # Corresponding Lecture: Core Spark RDD and Spark SQL
    # Rationale: Spark backend is written in Scala/Java; without Java, the
    #            Spark process cannot start.
    # ------------------------------------------------------------------------
    openjdk-17-jre-headless \
    # ------------------------------------------------------------------------
    # Network Communication Libraries (SSL, CURL, XML)
    # Corresponding Lab: sparklyr data source connection, Neo4j graph database
    #                    connection, knowledge graph construction.
    # Rationale: install.packages and sparklyr cloud data reading depend on
    #            these libraries.
    # ------------------------------------------------------------------------
    libssl-dev libcurl4-openssl-dev libxml2-dev \
    # ------------------------------------------------------------------------
    # System Tools and Compilation Dependencies
    # Corresponding Lab: RStudio environment setup, R package compilation,
    #                    TinyTeX installation.
    # Notes:
    #   wget gdebi-core       -- Download and install RStudio Server
    #   psmisc libuv1-dev     -- Dependencies for RStudio Server and fs package
    #   perl fontconfig       -- Dependencies for TinyTeX installation/runtime
    # ------------------------------------------------------------------------
    wget gdebi-core psmisc libuv1-dev perl fontconfig \
    # ------------------------------------------------------------------------
    # Build cleanup: clear cache to significantly reduce image size.
    # ------------------------------------------------------------------------
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Layer 2: RStudio Server (Web IDE)
# Description: Provides a browser-accessible integrated development environment
#              so students don't need to install RStudio Desktop locally.
# ============================================================================
# Corresponding Lab: RStudio interface familiarization, all R coding labs.
# Rationale: Provides variable environment window, Markdown preview, etc.
# Note: Bookworm package is unavailable, use jammy package instead.
# ----------------------------------------------------------------------------
RUN wget -q https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2024.04.2-764-amd64.deb -O /tmp/rstudio-server.deb && \
    apt-get update && \
    gdebi -n /tmp/rstudio-server.deb && \
    rm /tmp/rstudio-server.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create rstudio system user (RStudio Server needs to run sessions as this user).
RUN useradd -m -u 1000 -s /bin/bash rstudio && \
    echo "rstudio:rstudio" | chpasswd && \
    mkdir -p /home/rstudio/projects /home/rstudio/data && \
    chown -R rstudio:rstudio /home/rstudio

# ============================================================================
# Layer 3: R Language Packages
# ============================================================================
# Persist R package repository mirror.
RUN echo 'options(repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"))' >> $(R RHOME)/etc/Rprofile.site
RUN echo 'options(spark.install.dir = "/opt/spark")' >> $(R RHOME)/etc/Rprofile.site

# Install core course R packages in batch.
RUN R -e "install.packages(c( \
    # ------------------------------------------------------------------------
    # sparklyr
    # Corresponding Lab: Hands-on with sparklyr
    # Rationale: The only official interface connecting R to Spark clusters;
    #            translates dplyr syntax to Spark SQL.
    # ------------------------------------------------------------------------
    'sparklyr', \
    # ------------------------------------------------------------------------
    # rmarkdown
    # Corresponding Lab: R Markdown fundamentals
    # Rationale: Generates interactive teaching reports; assignments are
    #            submitted in .Rmd format.
    # ------------------------------------------------------------------------
    'rmarkdown', \
    # ------------------------------------------------------------------------
    # neo4r
    # Corresponding Lab: Neo4j graph database hands-on with Cypher queries
    # Rationale: Bridge for R to connect to Neo4j and execute Cypher queries.
    # ------------------------------------------------------------------------
    'neo4r', \
    # ------------------------------------------------------------------------
    # igraph
    # Corresponding Lab: Lecture 9 Network Science (centrality, community detection)
    # Rationale: Essential package for graph algorithms.
    # ------------------------------------------------------------------------
    'igraph', \
    # ------------------------------------------------------------------------
    # dplyr and ggplot2 (lightweight tidyverse core)
    # Corresponding Lab: data frame operations, Spark data cleaning, all data
    #                    visualization scenarios.
    # Rationale: sparklyr's tbl operations rely entirely on dplyr syntax;
    #            ggplot2 is used for plotting.
    # ------------------------------------------------------------------------
    'dplyr', \
    'ggplot2' \
    ), repos='${CRAN_MIRROR}')"

# Install a compatible bnlearn version separately.
# Corresponding Lab: Bayesian Networks in R - using the bnlearn package
# Rationale: The industrial-grade package for Bayesian network structure
#            learning in R; a core teaching content.
# Note: Pin version 4.8.1 to be compatible with the current R 4.2.2 environment.
RUN R -e "install.packages('https://cran.r-project.org/src/contrib/Archive/bnlearn/bnlearn_4.8.1.tar.gz', repos=NULL, type='source')"

# ============================================================================
# Layer 4: Apache Spark Runtime
# Description: This is the "engine" for sparklyr, not an R package.
# ============================================================================
# Corresponding Lab: First spark_connect()
# Corresponding Lecture: RDD and Unsupervised Learning (MLlib)
# Rationale: Pre-installation avoids a 10-20 minute download wait when students
#            run it for the first time.
# Version: Spark 3.4.0 (Hadoop 3 compatible)
# ----------------------------------------------------------------------------
# Notes: Install directly into /opt/spark using the shared R profile setting,
#        then allow the rstudio user to access it.
# ----------------------------------------------------------------------------
RUN --mount=type=cache,id=comp529-spark-3.4.0,target=/var/cache/comp529-spark,sharing=locked \
    wget --continue --tries=10 --timeout=120 --progress=dot:mega \
        --directory-prefix=/var/cache/comp529-spark \
        https://archive.apache.org/dist/spark/spark-3.4.0/spark-3.4.0-bin-hadoop3.tgz && \
    echo "67bc912e9192ef2159540cb480820e5466dfd91e907c97c5a4787587e3020be042b76c40c51854f2a5dbeb8c3775fe12d9021c1200c4704463ec644132243a69  /var/cache/comp529-spark/spark-3.4.0-bin-hadoop3.tgz" | sha512sum -c - && \
    R -e "sparklyr::spark_install_tar('/var/cache/comp529-spark/spark-3.4.0-bin-hadoop3.tgz'); sparklyr::spark_install(version = '3.4.0', hadoop_version = '3')" && \
    test -x /opt/spark/spark-3.4.0-bin-hadoop3/bin/spark-submit && \
    chown -R rstudio:rstudio /opt/spark && \
    chmod -R 755 /opt/spark

# ============================================================================
# Layer 5: PDF Support (TinyTeX)
# ============================================================================
# Corresponding Lab: R Markdown fundamentals (generate PDF reports)
# Rationale: Provides a lightweight LaTeX engine so .Rmd can be compiled to PDF.
# Notes: tlmgr is a Perl script; perl must already be installed on the system.
# ----------------------------------------------------------------------------
RUN R -e "install.packages('tinytex', repos='${CRAN_MIRROR}')" && \
    R -e "tinytex::install_tinytex(dir = '/opt/tinytex')" && \
    ln -sf /opt/tinytex/bin/*/tlmgr /usr/local/bin/tlmgr && \
    ln -sf /opt/tinytex/bin/*/* /usr/local/bin/ || true

# ============================================================================
# Layer 6: Runtime Configuration
# ============================================================================

# Expose RStudio Server default Web port.
ENV SPARK_HOME=/opt/spark/spark-3.4.0-bin-hadoop3

EXPOSE 8787

# Startup command:
# --server-daemonize=0  Run in foreground (prevent Docker container from exiting)
# --www-port=8787       Specify Web access port
# --auth-none=1         Simplify teaching, login without password
CMD ["/usr/lib/rstudio-server/bin/rserver", "--server-daemonize=0", "--www-port=8787", "--auth-none=1"]
