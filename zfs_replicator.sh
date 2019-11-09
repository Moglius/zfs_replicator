#!/usr/bin/env bash

######################################################################
####################### Globales #####################################
######################################################################
GLOBAL_POOL="subvol-3377-disk-1"
TARGET_HOST="10.X.X.X"
LOCAL_STORAGE="rpool/data/"
REMOTE_STORAGE="rpool/data/"
MAIL="matias.moglia@gba.gob.ar"
VMID="3377"
VM="0"

# Tomo el snap anterior en caso que haya uno para hacer el incremental
snap_anterior=$(zfs list -t snapshot | grep $GLOBAL_POOL |awk '/hourly/ {print $1}')

# Calculo para nombre generico
sec=$(date +%N%s | md5sum | awk '{print $1}')

# Si existe SNAP existente
if [[ $snap_anterior ]]
then
    # ahora hay que hacer el snap, enviar y borrar el anterior
    # tener en cuenta el manejo de errores y sobre todo este script mejor
    # ejecutarlo a mano antes de ponerlo en cron, por si tarda mas de 1 hora

    snap_anterior_rec=$(echo $snap_anterior |awk -F "/" '{print $NF }')

    snap_anterior_remoto=$(ssh $TARGET_HOST zfs list -t snapshot | grep $snap_anterior_rec |awk '/hourly/ {print $1}')

    snap_anterior_remoto_rec=$(echo $snap_anterior |awk -F "/" '{print $NF }')

    if [[ $snap_anterior_rec == $snap_anterior_remoto_rec ]]
    then

        # Se genera un nuevo snap y se envia en forma incremental al host
        res1=$(date +%s.%N)

        # Si es una vm, freeze con qm sino uso lxc
        if [[ $VM == "1" ]]; then
            qm agent $VMID fsfreeze-freeze
        else
            lxc-freeze $VMID
        fi

        zfs snapshot $LOCAL_STORAGE$GLOBAL_POOL@hourly_$sec

        # Si es una vm, unfreeze con qm sino uso lxc
        if [[ $VM == "1" ]]; then
            qm agent $VMID fsfreeze-thaw
        else
            lxc-unfreeze $VMID
        fi

        res2=$(date +%s.%N)
        dt=$(echo "$res2 - $res1" | bc)
        dd=$(echo "$dt/86400" | bc)
        dt2=$(echo "$dt-86400*$dd" | bc)
        dh=$(echo "$dt2/3600" | bc)
        dt3=$(echo "$dt2-3600*$dh" | bc)
        dm=$(echo "$dt3/60" | bc)
        ds=$(echo "$dt3-60*$dm" | bc)

        printf "Total runtime: %d:%02d:%02d:%02.4f\n" $dd $dh $dm $ds

        logger "SNAP creator: genero copia incremental $GLOBAL_POOL@hourly_$sec"
        echo "SNAP creator: genero copia incremental $GLOBAL_POOL@hourly_$sec"

        envio=$(zfs send --compressed -i $snap_anterior $LOCAL_STORAGE$GLOBAL_POOL@hourly_$sec | ssh $TARGET_HOST zfs recv $REMOTE_STORAGE$GLOBAL_POOL)

        if [[ $envio ]]
        then
            logger "SNAP creator: error envio de snapshot"
                echo "SNAP creator: error envio de snapshot"

            # se borra el snap actula en el host local
            zfs destroy $LOCAL_STORAGE$GLOBAL_POOL@hourly_$sec

            logger "SNAP creator: snapshot actual borrado"
                echo "SNAP creator: snapshot actual borrado"

            mail -s "SNAP creator: error envio" $MAIL <<< 'SNAP creator: error envio de snapshot'

        else
            logger "SNAP creator: copia enviada"
                echo "SNAP creator: copia enviada"

            # se borra el snap anterior en el host local
            zfs destroy $snap_anterior

            logger "SNAP creator: snapshot anterior borrado"
            echo "SNAP creator: snapshot anterior borrado"
        fi
    else
        logger "SNAP creator: Inconsistencia de snapshot local/remota"
        echo "SNAP creator: Inconsistencia de snapshot local/remota"

        mail -s "SNAP creator: Inconsistencia" $MAIL <<< 'SNAP creator: Inconsistencia de snapshot local/remota'
    fi


    #Se hace un loop para ver si en el host remoto existen snapshots mas viejos
    while IFS= read -r line
    do
           ## take some action on $line

        # Se toma la fecha de los snapshots remotos y la actual
          date=$(echo "$line" | awk '{print $4 " " $5 " " $6 " " $7}')
          snap=$(echo "$line" | awk '{print $1}')

        # Se pasa la fecha a formato de segudos desde 1970
          now=$(date +%s)
          date_snap=$(date -d "$date" +%s)

          delta=$(expr $now - $date_snap)

        # Se calcula las horas o dias en caso que se quiera expresar en ese formato
          dias=$(((($delta / 60) / 60) / 24))
        horas=$((($delta / 60) / 60))

        # solo dejo las ultimas 24 horas
        if [[ $horas -gt 24 ]]
        then
            # Se borra en caso que cumpla la condicion
            ssh -n $TARGET_HOST zfs destroy $snap
        fi

    done < <(ssh $TARGET_HOST zfs get creation | grep hourly | grep $GLOBAL_POOL)

else
    logger "SNAP creator: No existe copia existente, Primer Envio...."
    echo "SNAP creator: No existe copia existente, Primer Envio...."

    res1=$(date +%s.%N)

    # Si es una vm, freeze con qm sino uso lxc
    if [[ $VM == "1" ]]; then
        qm agent $VMID fsfreeze-freeze
    else
        lxc-freeze $VMID
    fi

    zfs snapshot $LOCAL_STORAGE$GLOBAL_POOL@hourly_$sec

    # Si es una vm, unfreeze con qm sino uso lxc
    if [[ $VM == "1" ]]; then
        qm agent $VMID fsfreeze-thaw
    else
        lxc-unfreeze $VMID
    fi

    zfs send --compressed $LOCAL_STORAGE$GLOBAL_POOL@hourly_$sec | ssh $TARGET_HOST zfs recv $REMOTE_STORAGE$GLOBAL_POOL

    res2=$(date +%s.%N)
    dt=$(echo "$res2 - $res1" | bc)
    dd=$(echo "$dt/86400" | bc)
    dt2=$(echo "$dt-86400*$dd" | bc)
    dh=$(echo "$dt2/3600" | bc)
    dt3=$(echo "$dt2-3600*$dh" | bc)
    dm=$(echo "$dt3/60" | bc)
    ds=$(echo "$dt3-60*$dm" | bc)

    printf "Total runtime: %d:%02d:%02d:%02.4f\n" $dd $dh $dm $ds

    logger "SNAP creator: No existe copia existente, Envio terminado."
    echo "SNAP creator: No existe copia existente, Envio terminado."

fi
