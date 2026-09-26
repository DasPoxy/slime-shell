.pragma library
// Shared between Slime Shell plugins in one shell process. Services only get a
// restricted view of the bar from the Omarchy host (and the bar none of the
// services), so the slime pieces register themselves here to find each other.

var bar = null            // slime.bar root
var notifications = null  // slime.notifications service

function register(item) { bar = item }
function unregister(item) { if (bar === item) bar = null }
function registerNotifications(item) { notifications = item }
function unregisterNotifications(item) { if (notifications === item) notifications = null }
