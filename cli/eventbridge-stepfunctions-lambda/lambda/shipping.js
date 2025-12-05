exports.handler = async (event) => {
    console.log('Processing shipping:', JSON.stringify(event));
    const { orderId, customerId } = event;

    // Simulate shipping processing
    await new Promise(resolve => setTimeout(resolve, 300));

    return {
        ...event,
        trackingNumber: `TRACK-${Date.now()}`,
        shippingStatus: 'shipped',
        estimatedDelivery: new Date(Date.now() + 3 * 24 * 60 * 60 * 1000).toISOString(),
        shippedAt: new Date().toISOString()
    };
};
