
#!/bin/bash
######################################################################################################
##---------------------------------------------------------------------------------------
## File name : check_icp.sh
## Description : Generate a result file to determine whether or not the system is healthy 
## Information : It is registered in crontab for automatic execution at a specific time every month. 
##               ex. (every 5 minute)  */5 * * * *  ~/shl/mon/check_icp.sh 1>/dev/null 2>&1
## ##### ICP #####
## 1. WebtoB Version
## 2. WebtoB License
## 3. WebtoB Engine
## 4. WebtoB Shared Memory
##
##=======================================================================================
##  version   date             author      reason
##---------------------------------------------------------------------------------------
##  1.01      2019.12.19       Chang Y.O   Annotation Standardization 
##  1.02      2019.12.24       Eom J.S     Modify check_etcd()
######################################################################################################
# ======<<<< Signal common processing logic (Start) >>>>==============================================
# trap ' echo "$(date +${logdatefmt}) $0 signal(SIGINT ) captured" | tee -a ${logfnm}; exit 1;' SIGINT
# trap ' echo "$(date +${logdatefmt}) $0 signal(SIGQUIT) captured" | tee -a ${logfnm}; exit 1;' SIGQUIT
# trap ' echo "$(date +${logdatefmt}) $0 signal(SIGTERM) captured" | tee -a ${logfnm}; exit 1;' SIGTERM 
# ======<<<< Signal common processing logic (End) >>>>================================================
######################################################################################################

######################################################################################################
# ======<<<< Important Global Variable Registration Area Marking Comment (Start) >>>>=================
# Log file name variable for storing script execution information:used in Signal common processing logic
# logfnm="/tmp/${USER}.script.trap.log"
# logdatefmt="%Y%m%d-%H:%M:%S"   # date/time format variable for logging info :used in Signal common logic
######################################################################################################

SCRIPT_VERSION=1.02
. /home/icpadm/shl/icp.env

ETCD_MEMBER=$(echo ${ETCD_POD_LIST} | wc -w)
ABSOLUTE_PATH="$(cd $(dirname "$0") && pwd -P)"
DATE=`date +%Y%m%d.%H%M%S`
USER=`whoami`
MYPID=`echo $$`
HEALTH_RESULT=0

      MON_LOG_DIR=/home/icpadm/shl/mon
          MON_LOG=${MON_LOG_DIR}/chk.log.$(date +%Y%m%d)
          PS_INFO=${MON_LOG_DIR}/ps_info.${RANDOM}
     NETSTAT_INFO=${MON_LOG_DIR}/netstat_info.${RANDOM}
      NOTOK_LISTS=${MON_LOG_DIR}/notok.list
    HEALTH_RESULT=${MON_LOG_DIR}/result.${RANDOM}
NETSTAT_INFO_FILE=${MON_LOG_DIR}/net_info/net_info.${DATE3}

          SMS_LOG=/tmp/mw.log

TMP1=${MON_LOG_DIR}/tmp1.${RANDOM}
TMP2=${MON_LOG_DIR}/tmp2.${RANDOM}

# ======<<<< Important Global Variable Registration Area Marking Comment (End) >>>>===================
######################################################################################################
# ======<<<< Function Registration Area Marking Comment (Start) >>>>==================================
#=====================================================================================================
# Common Function
#=====================================================================================================
###########################################################################
##  Function Name : print_msg 
##  Description : This function print a 'OK' message 
##  Information : The factor values are received and displayed accordiing to the prescribed format. 
###########################################################################
print_msg() {
    printf "[%s] %-10s _ %-20s : %-10s - [%s] %-10s %-10s %-10s %-10s\n" $1 $2 $3 $4 $5 $6 $7 $8 $9 | sed -e "s/ *$//g" | tee -a ${MON_LOG}
}

###########################################################################
##  Function Name : print_msg 
##  Description : This function print a 'NOT.OK' message 
##  Information : The factor values are received and displayed accordiing to the prescribed format. 
###########################################################################
print_msg_nok() {
    printf "[%s] %-10s _ %-20s : %-10s - [%6s] %-10s %-10s %-10s %-10s\n" $1 $2 $3 $4 $5 $6 $7 $8 $9 | sed -e "s/ *$//g" | tee -a ${MON_LOG}
    printf "[%s] %-10s _ %-20s : %-10s - [%6s] %-10s %-10s %-10s %-10s\n" $1 $2 $3 $4 $5 $6 $7 $8 $9 | sed -e "s/ *$//g" >> ${SMS_LOG}
    RESULT_TEMP=`cat ${HEALTH_RESULT}`
    RESULT_TEMP=`expr ${RESULT_TEMP} + 1`
    echo ${RESULT_TEMP} > ${HEALTH_RESULT}
}

###########################################################################
##  Function Name : common 
##  Description : This function is pre-worked and commonly used.    
##  Information : It generates the smslog, process information, netstat 
##                temporary file, and prints the script version.
###########################################################################
common()
{
    touch ${SMS_LOG}
    \chmod 777 ${SMS_LOG}

    touch ${TMP1}
    touch ${TMP2}
    touch ${PS_INFO}
    touch ${NETSTAT_INFO}
    echo 0 > ${HEALTH_RESULT}

    ps -ef | egrep "^root|^${USER}" > ${PS_INFO}
    netstat -nlt > ${NETSTAT_INFO}

    netstat -anp 2>/dev/null > ${NETSTAT_INFO_FILE}

    printf "SCRIPT VERSION=%s\n" ${SCRIPT_VERSION}
}

###########################################################################
##  Function Name : remove_tmp_files
##  Description : This function deletes temporary files. 
##  Information : This deletes temporary files such as process information,
##                netstat, and inspection results after inspection. 
###########################################################################
remove_tmp_files()
{
    gzip -f ${NETSTAT_INFO_FILE}
    OLD_NET=`echo ${NETSTAT_INFO_FILE} | awk -F "/" '{print $NF}' | awk -F "." '{print $1}'`
    find ${MON_LOG_DIR} -name "${OLD_NET}.`date -d 'yesterday' '+%Y%m%d'`*" -type f -exec rm -rf {} \;

    \rm ${TMP1} ${TMP2} ${PS_INFO} ${NETSTAT_INFO} ${HEALTH_RESULT} ${NOTOK_LISTS} ${CON_INFO} 2>/dev/null
}

###########################################################################
##  Function Name : paas_info_chk
##  Description : This function checks the JEUS version. 
##  Information : This function checks the JEUS version. 
###########################################################################
paas_info_chk()
{
    echo "PAAS_VERSION=ICP_3.2.0"
    echo "PAAS_HOME=/home/icpadm"
}

###########################################################################
##  Function Name : check_etcd
##  Description : This function print a 'NOT.OK' message 
##  Information : The factor values are received and displayed accordiing to the prescribed format. 
###########################################################################
check_etcd() {
   LEADER_CNT=0

   for ETCD_POD in ${ETCD_POD_LIST}
   do
      ETCD_IP=`echo ${ETCD_POD} | cut -d"-" -f3`

      IS_LEADER=$(kubectl -n kube-system exec ${ETCD_POD} -- sh -c "export ETCDCTL_API=3; /usr/local/bin/etcdctl --cert /etc/cfc/conf/etcd/client.pem --key /etc/cfc/conf/etcd/client-key.pem --cacert /etc/cfc/conf/etcd/ca.pem --endpoints https://${ETCD_IP}:4001 -w table endpoint status" | grep "https" | grep "true" | awk '{print $2}')

      if [ "${IS_LEADER}" != "" ]; then
         ((LEADER_CNT++))
         LEADER=${ETCD_POD}
         LEADER_IP=${ETCD_IP}
      fi
   done

   MEMBER_NO=$(kubectl -n kube-system exec ${LEADER} -- sh -c "export ETCDCTL_API=3; /usr/local/bin/etcdctl --cert /etc/cfc/conf/etcd/client.pem --key /etc/cfc/conf/etcd/client-key.pem --cacert /etc/cfc/conf/etcd/ca.pem --endpoints https://${LEADER_IP}:4001 member list" | wc -l)

   if [[ ${LEADER_CNT} -eq 1  && ${ETCD_MEMBER} -eq ${MEMBER_NO} ]]; then
      # echo ${LEADER} - ${MEMBER_NO}
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK" "${LEADER}/1_Leader/${MEMBER_NO}_Member"
   else
      # echo "Leader Count is not 1"
      print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "LEADER_CNT_IS_NOT_1/${MEMBER_NO}_Member"
   fi
}

###########################################################################
##  Function Name : check_proxy_vip
##  Description : This function print a 'NOT.OK' message 
##  Information : The factor values are received and displayed accordiing to the prescribed format. 
###########################################################################
check_proxy_vip() {
   kubectl get pod -n kube-system | grep k8s-proxy-keepalived | awk '{print $1}' | while read POD
   do
      STR=`kubectl logs ${POD} -n kube-system | grep "Entering MASTER STATE"`
      NODE=`echo ${POD} | sed -e "s/k8s-proxy-keepalived-//g"`

      if [ "${STR}" != "" ]; then
         # echo ${NODE} : ${STR}
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK" "${PROXY_VIP}/${NODE}" 

         echo ${FUNCNAME[0]} > ${TMP1}
      fi
   done

   if [ $(grep ${FUNCNAME[0]} ${TMP1} | wc -l) == 0 ]; then
       print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "NO_PROXY_VIP_CHECKED"
       > ${TMP1}
   fi
}

###########################################################################
##  Function Name : check_master_vip
##  Description : This function print a 'NOT.OK' message 
##  Information : The factor values are received and displayed accordiing to the prescribed format. 
###########################################################################
check_master_vip() {
   kubectl get pod -n kube-system | grep k8s-master-keepalived | awk '{print $1}' | while read POD
   do
      STR=`kubectl logs ${POD} -n kube-system | grep "Entering MASTER STATE"`
      NODE=`echo ${POD} | sed -e "s/k8s-master-keepalived-//g"`

      if [ "${STR}" != "" ]; then
         # echo ${NODE} : ${STR}
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK" "${MASTER_VIP}/${NODE}" 

         echo ${FUNCNAME[0]} > ${TMP1}
      fi
   done 

   if [ $(grep ${FUNCNAME[0]} ${TMP1} | wc -l) == 0 ]; then
       print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "NO_MASTER_VIP_CHECKED"
       > ${TMP1}
   fi
}

check_docker_login() {
   docker login ${DOCKER_REPOSITORY} 1>/dev/null 2>&1 

   if [ $? -ne 0 ]; then
      # echo "docker login NOT.OK ..."
      print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${DOCKER_REPOSITORY}"
   else
      # echo "docker login OK ..."
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK" "${DOCKER_REPOSITORY}"
   fi
}

check_auth_idp() {
   kubectl get pod -lk8s-app=auth-idp  -n kube-system -o wide  | grep "^auth-idp" | while read LINE
   do
      POD=`echo $LINE | awk '{print $1"/"$7}'`
      IS_OK=`echo $LINE | grep Running | wc -l`

      if [ "${POD}" != "" ]; then
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${POD}"
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${POD}"
      fi
   done
}

check_image_manager() {
   kubectl get pod -lapp=image-manager -n kube-system -o wide  | grep "^image-manager" | while read LINE
   do
      POD=`echo $LINE | awk '{print $1"/"$7}'`
      IS_OK=`echo $LINE | grep Running | wc -l`

      if [ "${POD}" != "" ]; then
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${POD}"
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${POD}"
      fi
   done
}

check_pod_run() {

   # NAMESPACE        NAME                                                              READY   STATUS
   # kube-system      regpod-checking                                                   0/1     Init:0/1            0          74m

   kubectl get pod --all-namespaces | grep -v "^NAMESPACE" | egrep -v "regpod-checking|vulnerability-advisor" > ${TMP1}

   NOT_OK_POD_CNT=$( cat ${TMP1} | egrep -v "Running|Completed" | wc -l )
       OK_POD_CNT=$( cat ${TMP1} | egrep    "Running|Completed" | wc -l )

   #echo $NOT_OK_POD_CNT
   #cat ${TMP1} | egrep -v "Running|Completed"
   #echo $OK_POD_CNT

   print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${OK_POD_CNT} PODs_Running"
   
   cat ${TMP1} | egrep -v "Running|Completed" | while read NS POD READY STATUS
   do
      print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${STATUS}/${POD}/${NS}"
   done
}

check_pod_cpu_top5() {
   # apih-prd         apih-kafka-0                                                     114m         7296Mi 

   kubectl top pod --all-namespaces | grep -v NAME | grep -v "kube-system" | sort -k3 -r -h | head -5 | while read NS POD CPU MEM
   do
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK.INFO"     "${CPU}/${MEM} ${NS}/${POD}"
   done
}

check_pod_mem_top5() {
   kubectl top pod --all-namespaces | grep -v NAME | grep -v "kube-system" | sort -k4 -r -h | head -5 | while read NS POD CPU MEM
   do
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK.INFO"     "${CPU}/${MEM} ${NS}/${POD}"
   done
}

check_ingress_ctl() {
   INGRESS_LABEL=$1

   # nginx-ingress-controller-gz5k7   1/1     Running   2          14d   10.1.47.23     172.31.163.101   <none>           <none>
   kubectl get pod -lapp=${INGRESS_LABEL} -o wide | grep -v "NAME" | while read POD READY STATUS RESTARTED UPTIME POD_IP NODE_IP D1 D2
   do
      if [ "${STATUS}" == "Running" ]; then
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${STATUS} ${POD}/${NODE_IP}"
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${STATUS} ${POD}/${NODE_IP}"
      fi
   done
}

check_node() {
   kubectl get node --show-labels | grep -v "^NAME" | while read NODE_IP STATUS ROLE UPTIME VER LABEL
   do
      HOST=`echo ${LABEL##*,hostname=} | cut -d, -f1`

      if [ "${STATUS}" == "Ready" ]; then
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${STATUS} ${HOST}/${NODE_IP}/${ROLE}"
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${STATUS} ${HOST}/${NODE_IP}/${ROLE}"
      fi
   done
}

check_ingress() {
   # apih-prd      apih-ingress-ex                              apihub.sktelecom.com,apihubadm.sktelecom.com   172.31.163.126                                 80      9d

   kubectl get ingress --all-namespaces | grep "^.*-prd.*" | while read NS INGRESS DOMAIN ADDR PORT UPTIME
   do
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${INGRESS}/${NS} ${DOMAIN}"
   done
}

check_svc_ep() {
   # apih-prd         apih-api-gateway                              10.1.48.32:8080,10.1.98.174:8080                                          6d21h

   kubectl get ep --all-namespaces | grep "^.*-prd.*" | sed -e "s/+.*more...//g" | while read NS ENDPOINTS POD_IP_PORTS AGE
   do
      if [ "${POD_IP_PORTS}" != "<none>" ]; then
         # print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${AGE} ${ENDPOINTS}/${NS} ${POD_IP_PORTS}"
         echo "${AGE} ${ENDPOINTS}/${NS} ${POD_IP_PORTS}" >> ${TMP1}
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${AGE} ${ENDPOINTS}/${NS} this_endpoints_is_empty"
      fi
   done

   OK_CNT=`cat ${TMP1} | wc -l`
   print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${OK_CNT} all_endpoints_is_mapped"
}

check_redis() {
   # apih-prd    redis-ha-server-0   3/3     Running   0          2d22h

   PASSWORD=rhddyd12~!
   kubectl get pod -lapp=redis-ha --all-namespaces | grep -v "^NAMESPACE" | while read NS POD READY STATUS RESTARTED AGE
   do
      REDIS_ROLE=$(kubectl -n ${NS} exec ${POD} -c redis -- sh -c "export REDISCLI_AUTH=${PASSWORD}; redis-cli INFO Replication" | grep "^role:" | cut -d":" -f2)

      ## ${REDIS_ROLE} has unknown padding characters
      ROLE=0
      if [ $(echo ${REDIS_ROLE} | grep master | wc -l) == 1 ]; then
         ROLE=MASTER
      else
         ROLE=SLAVE
      fi

      if [ "${STATUS}" == "Running" ]; then
         print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${ROLE} ${POD}/${NS}"
      else
         print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${ROLE} ${POD}/${NS}"
      fi
   done
}

check_prometheus() {

   curl -s -k -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8"              \
              -d "grant_type=password&username=${ICP_USER}&password=${ICP_PASS}&scope=openid" \
              https://${PROMETHEUS_API_URL}/idprovider/v1/auth/identitytoken > ${TMP1}

   ACCESS_TOKEN=`cat ${TMP1} | jq -r .access_token`

   STATUS=`curl -k -s -H  "Authorization: Bearer $ACCESS_TOKEN"  -X GET  "https://${PROMETHEUS_API_URL}/prometheus/api/v1/labels" | jq -r .status`

   if [ "${STATUS}" == "success" ]; then
      print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "${STATUS} https://${PROMETHEUS_API_URL}/prometheus/api/v1/labels"
   else
      print_msg_nok ${DATE} ${USER} ${FUNCNAME[0]} "NOT.OK" "${STATUS} https://${PROMETHEUS_API_URL}/prometheus/api/v1/labels"
   fi
}

check_kubecfg_crt() {
   print_msg     ${DATE} ${USER} ${FUNCNAME[0]} "OK"     "/etc/cfc/conf/kubecfg.crt kubecfg.key Validate_Limit at Master"
}

_main() {
   common

   paas_info_chk
   check_etcd
   check_master_vip
   check_proxy_vip
   check_node
   check_ingress_ctl  "nginx-ingress-controller"
   check_ingress_ctl  "nginx-ingress-controller-external"
   check_ingress
   check_svc_ep
   check_pod_run
   check_kubecfg_crt

   check_docker_login
   check_auth_idp
   check_image_manager

   check_redis
   check_prometheus
   # check_pod_cpu_top5
   # check_pod_mem_top5

   remove_tmp_files
}

_main
