/const makeOfflineNodeProcessor = () => {/i\
    const handleStatus = async (node) => {\
        try {\
            await sendMessageAck(node);\
        }\
        catch (error) {\
            onUnexpectedError(error, 'acking status stanza');\
        }\
    };
s/\['notification', handleNotification\]/['notification', handleNotification],/
/\['notification', handleNotification\],/a\
            ['status', handleStatus]
/ws.on('CB:notification', async (node) => {/,/});/{
/});/a\
    ws.on('CB:status', async (node) => {\
        await processNode('status', node, 'acking status stanza', handleStatus).catch(error => onUnexpectedError(error, 'acking status stanza'));\
    });
}
