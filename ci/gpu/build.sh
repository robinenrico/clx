#/usr/bin/env bash
set -e
NUMARGS=$#
ARGS=$*

# Logger function for build status output
function logger() {
  echo -e "\n>>>> $@\n"
}

# Arg parsing function
function hasArg {
    (( ${NUMARGS} != 0 )) && (echo " ${ARGS} " | grep -q " $1 ")
}

# Set path and build parallel level
export PATH=/conda/bin:/usr/local/cuda/bin:$PATH
export CUDA_REL=${CUDA_VERSION%.*}
export CUDA_SHORT=${CUDA_REL//./}

# Set home to the job's workspace
export HOME=$WORKSPACE

# Switch to project root; also root of repo checkout
cd $WORKSPACE
export GIT_DESCRIBE_TAG=`git describe --tags`
export MINOR_VERSION=`echo $GIT_DESCRIBE_TAG | grep -o -E '([0-9]+\.[0-9]+)'`

################################################################################
# SETUP - Check environment
################################################################################

logger "Get env..."
env

logger "Activate conda env..."
source activate gdf

logger "Check versions..."
python --version

# FIX Added to deal with Anancoda SSL verification issues during conda builds
conda config --set ssl_verify False

conda remove nomkl blas libblas

logger "conda install required packages"
conda install -c pytorch -c gwerbin \
    "cugraph=${MINOR_VERSION}" \
    "cuml=${MINOR_VERSION}" \
    "dask-cudf=${MINOR_VERSION}" \
    "pytorch=1.5.*" \
    "torchvision" \
    "scikit-learn" \
    "numpy>=1.17.3,<1.19.0" \
    "python-confluent-kafka" \
    "transformers" \
    "seqeval" \
    "python-whois" \
    "requests" \
    "cmake" \
    "cython" \
    "pytest" \
    "s3fs" \
    "ipython" \
    "matplotlib" \
    "nbconvert"

# Install the master version of dask, distributed, and cudatashader
logger "pip install git+https://github.com/dask/distributed.git --upgrade --no-deps"
pip install "git+https://github.com/dask/distributed.git" --upgrade --no-deps
logger "pip install git+https://github.com/dask/dask.git --upgrade --no-deps"
pip install "git+https://github.com/dask/dask.git" --upgrade --no-deps
logger "pip install git+https://github.com/rapidsai/cudatashader.git"
pip install "git+https://github.com/rapidsai/cudatashader.git"
logger "pip install mockito"
pip install mockito

conda list

################################################################################
# BUILD - Build libclx and clx from source
################################################################################

logger "Build libclx and clx..."
$WORKSPACE/build.sh clean libclx clx

################################################################################
# TEST - Test python package
################################################################################

if hasArg --skip-tests; then
    logger "Skipping Tests..."
else
    cd ${WORKSPACE}/python
    py.test --ignore=ci --cache-clear --junitxml=${WORKSPACE}/junit-clx.xml -v
    ${WORKSPACE}/ci/gpu/test-notebooks.sh 2>&1 | tee nbtest.log
    python ${WORKSPACE}/ci/utils/nbtestlog2junitxml.py nbtest.log
fi
