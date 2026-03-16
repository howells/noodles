function ndev
    set -l logdir ~/.cache/noodles/logs
    set -l logfile $logdir/(basename $PWD).log
    mkdir -p $logdir
    echo "" > $logfile

    if test -f bun.lockb; or test -f bun.lock
        bun run dev 2>&1 | tee $logfile
    else if test -f pnpm-lock.yaml
        pnpm run dev 2>&1 | tee $logfile
    else if test -f yarn.lock
        yarn dev 2>&1 | tee $logfile
    else
        npm run dev 2>&1 | tee $logfile
    end
end
