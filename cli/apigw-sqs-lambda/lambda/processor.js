exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'messages from SQS');

    const results = [];
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            console.log('Processing message:', record.messageId);
            console.log('Message body:', JSON.stringify(body, null, 2));

            // Add your business logic here
            const result = {
                messageId: record.messageId,
                body: body,
                processedAt: new Date().toISOString(),
                status: 'success'
            };

            results.push(result);
            console.log('Processed successfully:', record.messageId);
        } catch (error) {
            console.error('Error processing message:', record.messageId, error);
            throw error; // Rethrow to trigger retry/DLQ
        }
    }

    console.log('Processed', results.length, 'messages');
    return { batchItemFailures: [] };
};
