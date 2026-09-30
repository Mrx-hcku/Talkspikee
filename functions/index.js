 const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// 1. Global Feed Notification: Jab bhi koi naya post bane
exports.sendNewPostNotification = functions.firestore
    .document('posts/{postId}')
    .onCreate(async (snapshot, context) => {
        const postData = snapshot.data();

        const message = {
            notification: {
                title: 'Nayi Discussion Shuru Hui! 🚀',
                body: `${postData.author}: "${postData.content.substring(0, 60)}..."`,
            },
            topic: 'global_feed', // Sabhi users jo is topic se jude hain
        };

        try {
            await admin.messaging().send(message);
            console.log('Global post notification successfully sent!');
        } catch (error) {
            console.error('Error sending global notification:', error);
        }
    });

// 2. Personal Notification: Jab koi Like, Reply, ya Follow kare
exports.sendPersonalNotification = functions.firestore
    .document('notifications/{notificationId}')
    .onCreate(async (snapshot, context) => {
        const notifData = snapshot.data();
        const receiverId = notifData.receiverId; // Jisko notification milni hai

        if (!receiverId) {
            console.log('Receiver ID nahi mili!');
            return;
        }

        // Firestore se target user ka FCM token nikalna
        const userDoc = await admin.firestore().collection('users').doc(receiverId).get();
        
        if (!userDoc.exists || !userDoc.data().fcmToken) {
            console.log('Target user ka FCM token nahi mila!');
            return;
        }

        const fcmToken = userDoc.data().fcmToken;

        const message = {
            token: fcmToken,
            notification: {
                title: notifData.title || 'TalkSpike Notification',
                body: notifData.body || 'Aapko ek naya interaction mila hai.',
            },
        };

        try {
            await admin.messaging().send(message);
            console.log('Personal targeted notification successfully sent!');
        } catch (error) {
            console.error('Error sending personal notification:', error);
        }
    });

