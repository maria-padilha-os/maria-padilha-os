# ~/.bash_logout -- clear the console on logout when supported.
if [ -x /usr/bin/clear_console ]; then
    /usr/bin/clear_console -q
fi
