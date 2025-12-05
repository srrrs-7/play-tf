exports.handler = async (event) => {
    console.log('Sending notification:', JSON.stringify(event));
    const { orderId, customerId, trackingNumber, paymentStatus, shippingStatus } = event;

    console.log(`Notification sent to customer ${customerId}:`, {
        orderId,
        paymentStatus,
        shippingStatus,
        trackingNumber
    });

    return {
        ...event,
        notified: true,
        notifiedAt: new Date().toISOString(),
        message: 'Order confirmation sent successfully'
    };
};
