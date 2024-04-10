import tarfile
import gzip
import zipfile
from io import BytesIO
import boto3
import logging, os
from pathlib import Path

levels = {
    'critical': logging.CRITICAL,
    'error': logging.ERROR,
    'warn': logging.WARNING,
    'info': logging.INFO,
    'debug': logging.DEBUG
}
logger = logging.getLogger()
try:
    logger.setLevel(levels.get(os.getenv('LOG_LEVEL', 'info').lower()))
except KeyError:
    logger.setLevel(logging.INFO)

s3 = boto3.client('s3')


def lambda_handler(event, context):
    bucket_name = event['Bucket']
    prefix = event['Prefix']
    remove_archive = False if "RemoveArchive" in event and event['RemoveArchive'].lower() == "false" else True
    logger.info("Bucket: %s, Prefix: %s, RemoveArchive: %s", bucket_name, prefix, remove_archive)

    try:
        s3_client = boto3.resource('s3')
        bucket = s3_client.Bucket(bucket_name)
        archive_keys = list(filter(lambda k: k != event['Prefix'] and (k.endswith('.gz') or k.endswith('.zip')), (_.key for _ in bucket.objects.filter(Prefix=prefix))))

        pathnames = []
        extracted = []
        for archive_key in archive_keys:
            pathname = os.path.dirname(archive_key)
            pathnames.append(pathname)
            tmp_pathname = os.path.join("/tmp", pathname)

            object = s3_client.Object(bucket_name, archive_key)
            bytes_object = object.get()['Body'].read()
            if archive_key.endswith('.tar.gz'):
                with tarfile.open(fileobj=BytesIO(bytes_object)) as tar_file:
                    tar_file.extractall(path=tmp_pathname)
            elif archive_key.endswith('.gz'):
                os.makedirs(tmp_pathname, exist_ok=True)
                with open(os.path.join(tmp_pathname, Path(archive_key).stem), 'wb+') as gz_file:
                    gz_file.write(gzip.decompress(bytes_object))
            elif archive_key.endswith('.zip'):
                os.makedirs(tmp_pathname, exist_ok=True)
                with zipfile.ZipFile(BytesIO(bytes_object)) as zip_file:
                    zip_file.extractall(path=tmp_pathname,members=list(filter(lambda k: not k.startswith('__MACOSX'), zip_file.namelist())))

            count = 0
            for filename in os.listdir(tmp_pathname):
                tmp_file = os.path.join(tmp_pathname, filename)
                new_key = os.path.join(pathname, filename)
                bucket.Object(new_key).upload_file(tmp_file)
                count = count + 1
                extracted.append(new_key)

            logger.info("Successfully extracted %s file%s from %s.", count, "" if count == 1 else "s", archive_key)
            if remove_archive:
                object.delete()
                logger.info("Successfully removed archive %s.", archive_key)
        if not archive_keys:
            logger.info("No matching archives found for Prefix %s.", prefix)
    except Exception as e:
        logger.error("Failed to extract files from archives in Bucket %s, Prefix %s:", bucket_name, prefix)
        raise e

    return {
        'Pathnames': pathnames,
        'Extracted': extracted
    }
