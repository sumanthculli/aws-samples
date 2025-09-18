import json
import boto3
import email
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from fpdf import FPDF
import io
import re
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
ses_client = boto3.client('ses')

def lambda_handler(event, context):
    """
    AWS Lambda handler for converting SES emails to PDF
    Triggered by S3 events when SES stores incoming emails
    """
    try:
        # Parse the S3 event
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = record['s3']['object']['key']
            
            # Skip processing if this is a PDF file (to avoid recursive processing)
            if object_key.endswith('.pdf') or '/pdf/' in object_key:
                logger.info(f"Skipping PDF file: {object_key}")
                continue
            
            logger.info(f"Processing email from bucket: {bucket_name}, key: {object_key}")
            
            # Download the email from S3
            email_content = download_email_from_s3(bucket_name, object_key)
            
            # Parse the email
            parsed_email = parse_email(email_content)
            
            # Convert email to PDF
            pdf_buffer = convert_email_to_pdf(parsed_email)
            
            # Upload PDF to S3
            pdf_key = upload_pdf_to_s3(bucket_name, object_key, pdf_buffer)
            
            logger.info(f"Successfully converted email to PDF: {pdf_key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Email(s) successfully converted to PDF')
        }
        
    except Exception as e:
        logger.error(f"Error processing email: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def download_email_from_s3(bucket_name, object_key):
    """Download email content from S3"""
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
        return response['Body'].read()
    except Exception as e:
        logger.error(f"Error downloading email from S3: {str(e)}")
        raise

def parse_email(email_content):
    """Parse email content and extract relevant information"""
    try:
        # Parse the email
        msg = email.message_from_bytes(email_content)
        
        # Extract email metadata
        email_data = {
            'subject': msg.get('Subject', 'No Subject'),
            'from': msg.get('From', 'Unknown Sender'),
            'to': msg.get('To', 'Unknown Recipient'),
            'date': msg.get('Date', 'Unknown Date'),
            'message_id': msg.get('Message-ID', 'Unknown'),
            'body_text': '',
            'body_html': '',
            'attachments': []
        }
        
        # Extract email body
        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get('Content-Disposition', ''))
                
                if content_type == 'text/plain' and 'attachment' not in content_disposition:
                    email_data['body_text'] = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                elif content_type == 'text/html' and 'attachment' not in content_disposition:
                    email_data['body_html'] = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                elif 'attachment' in content_disposition:
                    filename = part.get_filename()
                    if filename:
                        email_data['attachments'].append({
                            'filename': filename,
                            'content_type': content_type,
                            'size': len(part.get_payload(decode=True)) if part.get_payload(decode=True) else 0
                        })
        else:
            # Single part message
            content_type = msg.get_content_type()
            if content_type == 'text/plain':
                email_data['body_text'] = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
            elif content_type == 'text/html':
                email_data['body_html'] = msg.get_payload(decode=True).decode('utf-8', errors='ignore')
        
        return email_data
        
    except Exception as e:
        logger.error(f"Error parsing email: {str(e)}")
        raise

def convert_email_to_pdf(email_data):
    """Convert parsed email data to PDF format using FPDF"""
    try:
        # Create PDF
        pdf = FPDF()
        pdf.add_page()
        pdf.set_auto_page_break(auto=True, margin=15)
        
        # Title
        pdf.set_font('Arial', 'B', 16)
        pdf.set_text_color(46, 134, 171)  # Blue color
        pdf.cell(0, 10, 'Email Conversion Report', ln=True, align='C')
        pdf.ln(10)
        
        # Email metadata section
        pdf.set_font('Arial', 'B', 14)
        pdf.set_text_color(162, 59, 114)  # Purple color
        pdf.cell(0, 10, 'Email Details', ln=True)
        pdf.ln(5)
        
        # Reset to black for content
        pdf.set_text_color(0, 0, 0)
        pdf.set_font('Arial', '', 10)
        
        # Email metadata
        metadata_items = [
            f"Subject: {clean_text_for_pdf(email_data['subject'])}",
            f"From: {clean_text_for_pdf(email_data['from'])}",
            f"To: {clean_text_for_pdf(email_data['to'])}",
            f"Date: {clean_text_for_pdf(email_data['date'])}",
            f"Message ID: {clean_text_for_pdf(email_data['message_id'])}"
        ]
        
        for item in metadata_items:
            # Clean and format the item
            clean_item = clean_text_for_pdf(item)
            # Handle long lines by wrapping
            if len(clean_item) > 85:
                lines = wrap_text(clean_item, 85)
                for i, line in enumerate(lines):
                    # Indent continuation lines
                    prefix = "    " if i > 0 else ""
                    pdf.cell(0, 6, prefix + line, ln=True)
            else:
                pdf.cell(0, 6, clean_item, ln=True)
        
        pdf.ln(10)
        
        # Email body section
        if email_data['body_text']:
            pdf.set_font('Arial', 'B', 14)
            pdf.set_text_color(162, 59, 114)
            pdf.cell(0, 10, 'Email Content', ln=True)
            pdf.ln(5)
            
            pdf.set_text_color(0, 0, 0)
            pdf.set_font('Arial', '', 10)
            
            # Process email body text
            text_content = clean_text_for_pdf(email_data['body_text'])
            
            # Split into lines and process each one
            lines = text_content.split('\n')
            
            for i, line in enumerate(lines):
                line = line.strip()
                
                if not line:
                    # Empty line - add some space
                    pdf.ln(3)
                elif line.startswith('=') and len(set(line)) == 1:
                    # Section divider (like ========)
                    pdf.ln(2)
                    pdf.set_font('Arial', 'B', 10)
                    pdf.cell(0, 5, '-' * 50, ln=True, align='C')
                    pdf.set_font('Arial', '', 10)
                    pdf.ln(2)
                elif line.isupper() and len(line) > 10:
                    # Section headers (all caps)
                    pdf.ln(3)
                    pdf.set_font('Arial', 'B', 11)
                    pdf.cell(0, 6, line, ln=True)
                    pdf.set_font('Arial', '', 10)
                    pdf.ln(1)
                elif line.startswith('-') or line.startswith('*'):
                    # Bullet points (convert • to - in clean_text_for_pdf)
                    if len(line) > 85:
                        wrapped_lines = wrap_text(line, 85)
                        for j, wrapped_line in enumerate(wrapped_lines):
                            prefix = "  " if j > 0 else ""
                            pdf.cell(0, 5, prefix + wrapped_line, ln=True)
                    else:
                        pdf.cell(0, 5, line, ln=True)
                else:
                    # Regular text
                    if len(line) > 85:
                        wrapped_lines = wrap_text(line, 85)
                        for wrapped_line in wrapped_lines:
                            pdf.cell(0, 5, wrapped_line, ln=True)
                    else:
                        pdf.cell(0, 5, line, ln=True)
        
        elif email_data['body_html']:
            pdf.set_font('Arial', 'B', 14)
            pdf.set_text_color(162, 59, 114)
            pdf.cell(0, 10, 'Email Content (HTML)', ln=True)
            pdf.ln(5)
            
            pdf.set_text_color(0, 0, 0)
            pdf.set_font('Arial', '', 10)
            
            # Enhanced HTML to text conversion
            html_text = strip_html_tags(email_data['body_html'])
            html_text = clean_text_for_pdf(html_text)
            
            # Split into lines and process each one (same logic as text)
            lines = html_text.split('\n')
            
            for line in lines:
                line = line.strip()
                
                if not line:
                    # Empty line - add some space
                    pdf.ln(3)
                elif line.startswith('-') or line.startswith('*'):
                    # Bullet points from HTML lists (• converted to - in clean_text_for_pdf)
                    if len(line) > 85:
                        wrapped_lines = wrap_text(line, 85)
                        for j, wrapped_line in enumerate(wrapped_lines):
                            prefix = "  " if j > 0 else ""
                            pdf.cell(0, 5, prefix + wrapped_line, ln=True)
                    else:
                        pdf.cell(0, 5, line, ln=True)
                else:
                    # Regular text
                    if len(line) > 85:
                        wrapped_lines = wrap_text(line, 85)
                        for wrapped_line in wrapped_lines:
                            pdf.cell(0, 5, wrapped_line, ln=True)
                    else:
                        pdf.cell(0, 5, line, ln=True)
        
        # Attachments section
        if email_data['attachments']:
            pdf.ln(10)
            pdf.set_font('Arial', 'B', 14)
            pdf.set_text_color(162, 59, 114)
            pdf.cell(0, 10, 'Attachments', ln=True)
            pdf.ln(5)
            
            pdf.set_text_color(0, 0, 0)
            pdf.set_font('Arial', '', 10)
            
            for attachment in email_data['attachments']:
                att_info = f"- {attachment['filename']} ({attachment['content_type']}, {attachment['size']} bytes)"
                att_info = clean_text_for_pdf(att_info)
                if len(att_info) > 85:
                    wrapped_lines = wrap_text(att_info, 85)
                    for i, wrapped_line in enumerate(wrapped_lines):
                        # Indent continuation lines
                        prefix = "  " if i > 0 else ""
                        pdf.cell(0, 5, prefix + wrapped_line, ln=True)
                else:
                    pdf.cell(0, 5, att_info, ln=True)
                pdf.ln(2)
        
        # Optional footer (can be disabled by setting environment variable)
        if os.environ.get('INCLUDE_FOOTER', 'true').lower() == 'true':
            pdf.ln(15)
            pdf.set_font('Arial', 'I', 8)
            pdf.set_text_color(128, 128, 128)
            footer_text = f"Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}"
            pdf.cell(0, 5, footer_text, ln=True, align='C')
        
        # Get PDF content as bytes
        pdf_content = pdf.output(dest='S')
        
        # Create buffer
        buffer = io.BytesIO(pdf_content.encode('latin-1') if isinstance(pdf_content, str) else pdf_content)
        
        return buffer
        
    except Exception as e:
        logger.error(f"Error converting email to PDF: {str(e)}")
        raise

def clean_text_for_pdf(text):
    """Clean text for PDF rendering while preserving formatting"""
    if not text:
        return ""
    
    # Decode HTML entities first
    text = text.replace('&lt;', '<')
    text = text.replace('&gt;', '>')
    text = text.replace('&amp;', '&')
    text = text.replace('&quot;', '"')
    text = text.replace('&apos;', "'")
    text = text.replace('&nbsp;', ' ')
    
    # Replace common Unicode characters with ASCII equivalents
    text = text.replace('—', '-')  # Em dash
    text = text.replace('–', '-')  # En dash
    text = text.replace(''', "'")  # Left single quote
    text = text.replace(''', "'")  # Right single quote
    text = text.replace('"', '"')  # Left double quote
    text = text.replace('"', '"')  # Right double quote
    text = text.replace('…', '...')  # Ellipsis
    text = text.replace('•', '-')  # Bullet point
    text = text.replace('→', '->')  # Right arrow
    text = text.replace('←', '<-')  # Left arrow
    
    # Handle non-ASCII characters by removing them
    text = text.encode('ascii', 'ignore').decode('ascii')
    
    # Only clean up excessive whitespace, preserve line breaks
    text = re.sub(r'[ \t]+', ' ', text)  # Multiple spaces/tabs to single space
    text = re.sub(r'\n[ \t]+', '\n', text)  # Remove spaces at start of lines
    text = re.sub(r'[ \t]+\n', '\n', text)  # Remove spaces at end of lines
    
    return text.strip()

def strip_html_tags(html_text):
    """Enhanced HTML tag removal and formatting"""
    if not html_text:
        return ""
    
    # Replace common HTML elements with text equivalents
    html_text = re.sub(r'<br\s*/?>', '\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<p\s*/?>', '\n\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'</p>', '', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<h[1-6][^>]*>', '\n\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'</h[1-6]>', '\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<li[^>]*>', '\n- ', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'</li>', '', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<ul[^>]*>|</ul>', '\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<ol[^>]*>|</ol>', '\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'<div[^>]*>', '\n', html_text, flags=re.IGNORECASE)
    html_text = re.sub(r'</div>', '', html_text, flags=re.IGNORECASE)
    
    # Remove all remaining HTML tags
    clean = re.compile('<.*?>')
    text = re.sub(clean, '', html_text)
    
    # Decode HTML entities
    text = text.replace('&nbsp;', ' ')
    text = text.replace('&amp;', '&')
    text = text.replace('&lt;', '<')
    text = text.replace('&gt;', '>')
    text = text.replace('&quot;', '"')
    text = text.replace('&apos;', "'")
    text = text.replace('&#39;', "'")
    text = text.replace('&#x27;', "'")
    
    # Clean up whitespace
    text = re.sub(r'\n\s*\n\s*\n', '\n\n', text)  # Multiple line breaks to double
    text = re.sub(r'[ \t]+', ' ', text)  # Multiple spaces/tabs to single space
    
    return text.strip()

def wrap_text(text, width):
    """Simple text wrapping function"""
    words = text.split(' ')
    lines = []
    current_line = []
    current_length = 0
    
    for word in words:
        if current_length + len(word) + 1 <= width:
            current_line.append(word)
            current_length += len(word) + 1
        else:
            if current_line:
                lines.append(' '.join(current_line))
            current_line = [word]
            current_length = len(word)
    
    if current_line:
        lines.append(' '.join(current_line))
    
    return lines

def upload_pdf_to_s3(bucket_name, original_key, pdf_buffer):
    """Upload generated PDF to S3"""
    try:
        # Generate PDF key based on original email key
        # Extract the filename from the original key and ensure proper path structure
        if original_key.startswith('emails/'):
            # Remove 'emails/' prefix and any existing 'pdf/' folders
            filename = original_key.replace('emails/', '').replace('pdf/', '')
            # Remove .txt extension if present
            if filename.endswith('.txt'):
                filename = filename[:-4]
            # Ensure .pdf extension
            if not filename.endswith('.pdf'):
                filename += '.pdf'
            # Create the correct PDF path
            pdf_key = f'emails/pdf/{filename}'
        else:
            # Fallback for unexpected key format
            pdf_key = f'emails/pdf/{original_key.split("/")[-1]}'
            if not pdf_key.endswith('.pdf'):
                pdf_key = pdf_key.replace('.txt', '') + '.pdf'
        
        # Upload PDF to S3
        s3_client.put_object(
            Bucket=bucket_name,
            Key=pdf_key,
            Body=pdf_buffer.getvalue(),
            ContentType='application/pdf',
            Metadata={
                'source': 'ses-email-conversion',
                'original-key': original_key,
                'converted-at': datetime.now().isoformat()
            }
        )
        
        logger.info(f"PDF uploaded to S3: s3://{bucket_name}/{pdf_key}")
        return pdf_key
        
    except Exception as e:
        logger.error(f"Error uploading PDF to S3: {str(e)}")
        raise