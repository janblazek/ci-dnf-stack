# Build
# -----
# $ podman build --build-arg TYPE=local -t dnf-bot/ci-dnf-stack:f33 -f Dockerfile.f33
#
#
# Run
# ---
# $ podman run -it dnf-bot/ci-dnf-stack:f33 behave -Ddnf_executable=dnf -t~xfail --junit --junit-directory=/opt/behave/junit/ [--wip --no-skipped]
#
#
# Build types
# -----------
# distro
#       install distro packages
# copr
#       install distro packages
#       then upgrade to copr packages
# local
#       install distro packages
#       then upgrade to copr packages
#       then install packages from local rpms/ folder
#       install also additional tools for debugging in the container


FROM fedora:33
ENV LANG C
ARG TYPE=local
ARG OSVERSION=fedora__33



# disable deltas and weak deps
RUN set -x && \
    echo -e "deltarpm=0" >> /etc/dnf/dnf.conf && \
    echo -e "install_weak_deps=0" >> /etc/dnf/dnf.conf


# install fakeuname from dnf-nightly copr repo
RUN set -x && \
    dnf -y install dnf-plugins-core; \
    dnf -y copr enable rpmsoftwaremanagement/dnf-nightly; \
    dnf -y install fakeuname;


# if not TYPE == copr nor local, disable nightly copr
RUN set -x && \
    if [ ! "$TYPE" == "copr" -a ! "$TYPE" == "local" ]; then \
        dnf -y copr disable rpmsoftwaremanagement/dnf-nightly; \
    fi


# upgrade all packages to the latest available versions
RUN set -x && \
    dnf -y --refresh upgrade


# install the test environment and additional packages
RUN set -x && \
    dnf -y install \
        # behave and test requirements
        findutils \
        glibc-langpack-en \
        libfaketime \
        openssl \
        python3-behave \
        python3-pexpect \
        python3-pip \
        rpm-build \
        rpm-sign \
        sqlite \
        attr \
        # if TYPE == local, install debugging tools
        $(if [ "$TYPE" == "local" ]; then \
            echo \
                less \
                openssh-clients \
                procps-ng \
                psmisc \
                screen \
                strace \
                tcpdump \
                vim-enhanced \
                vim-minimal \
                wget \
            ; \
        fi) \
        # install dnf stack
        createrepo_c \
        dnf \
        yum \
        dnf-plugins-core \
        dnf-utils \
        dnf-automatic \
        # all plugins with the same version as dnf-utils
        $(dnf repoquery dnf-utils --latest-limit=1 -q --qf="python*-dnf-plugin-*-%{version}-%{release}") \
        # extras plugins that are being tested
        python3-dnf-plugin-system-upgrade \
        libdnf \
        microdnf \
        # install third party plugins
        dnf-plugin-swidtags \
        zchunk && \
    pip install 'pyftpdlib'


# install local RPMs if available
COPY ./rpms/ /opt/behave/rpms/
RUN rm /opt/behave/rpms/*-{devel,debuginfo,debugsource}*.rpm; \
    if [ -n "$(find /opt/behave/rpms/ -maxdepth 1 -name '*.rpm' -print -quit)" ]; then \
        dnf -y install /opt/behave/rpms/*.rpm --disableplugin=local; \
    fi


# copy test suite
COPY ./dnf-behave-tests/ /opt/behave/

# set os userdata for behave
RUN echo -e "\
[behave.userdata]\n\
destructive=yes\n\
os=$OSVERSION" > /opt/behave/behave.ini

RUN set -x && \
    rm -rf "/opt/behave/fixtures/certificates/testcerts/" && \
    rm -rf "/opt/behave/fixtures/gpgkeys/keys/" && \
    rm -rf "/opt/behave/fixtures/repos/"

# build test repos from sources
RUN set -x && \
    cd /opt/behave/fixtures/specs/ && \
    ./build.sh --force-rebuild


WORKDIR /opt/behave
