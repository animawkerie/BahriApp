import os
import pandas as pd
from google.cloud import firestore

def export_data(export_type, output_dir):
    """
    Exports data from Firestore and generates a CSV based on export_type.
    export_type: str - The type of data to export ('Keystroke Data', 'Swipe Data', 'Tap Data')
    output_dir: str - Directory to save the CSV file
    """
    try:
        # Normalize the output directory to avoid escape sequence issues
        output_dir = output_dir.replace("\\", "/")
        print(f"Output directory: {output_dir}")

        # Initialize Firestore client
        db = firestore.Client()

        # Define main collection and subcollection based on export_type
        main_collection = 'users'
        subcollection_map = {
            'Keystroke Data': 'KeyStrokeData',
            'Swipe Data': 'swipeData',
            'Tap Data': 'tapData'
        }

        subcollection = subcollection_map.get(export_type)
        if not subcollection:
            print(f"Invalid export type: {export_type}")
            return f'Invalid export type: {export_type}'

        users = db.collection(main_collection).stream()

        data = []
        for user in users:
            user_dict = user.to_dict()
            user_id = user.id
            print(f"Processing user: {user_id}")
            sub_docs = db.collection(main_collection).document(user_id).collection(subcollection).stream()

            for doc in sub_docs:
                doc_dict = doc.to_dict()
                combined = {
                    'id': user_id,
                    'Email': user_dict.get('Email', ''),
                    'Date of Birth': user_dict.get('dateOfBirth', ''),
                    'skillLevel': user_dict.get('skillLevel', ''),
                    'gender': user_dict.get('gender', ''),
                    'Sentence': doc_dict.get('Sentence', ''),
                    'completeUserInput': doc_dict.get('completeUserInput', ''),
                    'keystrokeData': doc_dict.get('keystrokeData', ''),
                }
                data.append(combined)

        if not data:
            print("No data found to export.")
            return "No data to export."

        # Create DataFrame
        df = pd.DataFrame(data)
        print(f"DataFrame created with shape: {df.shape}")

        # Define the CSV file path
        csv_filename = f'{export_type.replace(" ", "_").lower()}.csv'
        csv_path = os.path.join(output_dir, csv_filename)
        print(f"Saving CSV to: {csv_path}")

        # Export to CSV
        df.to_csv(csv_path, index=False)

        print(f"Export successful: {csv_path}")
        return f'Exported {export_type} to {csv_path} successfully.'

    except Exception as e:
        print(f"Error during export: {e}")
        return f'Error exporting data: {e}'
