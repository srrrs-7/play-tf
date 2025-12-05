exports.handler = async (event) => {
    console.log('Validating order:', JSON.stringify(event));
    const { orderId, items } = event.detail || event;

    if (!orderId || !items || items.length === 0) {
        throw new Error('Invalid order: missing required fields');
    }

    const totalAmount = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);

    return {
        ...event,
        validated: true,
        totalAmount,
        validatedAt: new Date().toISOString()
    };
};
