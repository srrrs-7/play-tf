exports.handler = async (event) => {
    console.log('Processing payment:', JSON.stringify(event));
    const { orderId, totalAmount, customerId } = event;

    // Simulate payment processing
    await new Promise(resolve => setTimeout(resolve, 500));

    const paymentSuccessful = Math.random() > 0.1; // 90% success rate

    if (!paymentSuccessful) {
        throw new Error('Payment processing failed');
    }

    return {
        ...event,
        paymentId: `PAY-${Date.now()}`,
        paymentStatus: 'completed',
        paidAt: new Date().toISOString()
    };
};
