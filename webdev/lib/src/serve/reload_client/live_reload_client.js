(function () {
    var _buildUpdatesProtocol = '$buildResults';

    var ws = new WebSocket('ws://' + location.host, [_buildUpdatesProtocol]);
    ws.onmessage = function (event) {
        location.reload();
    };
})()
