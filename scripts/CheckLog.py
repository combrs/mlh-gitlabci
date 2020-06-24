#!/usr/bin/python

import glob
import logging
import logging.config


logging.config.fileConfig('log.conf')

list_files = glob.glob('*.log')


def read_file(file):
    with open(file) as file:
        o_file = file.readlines()

    for s in o_file:
        if 'PB Server not restarted' in s:
            end_index = o_file.index(s)
            return o_file[:end_index]


def check(file):
    for st in file:
        if 'Element' in st:
            el_id = file.index(st)
            dst = file[el_id:el_id + 3]
            split_dst_0 = dst[0].split()
            split_dst_1 = dst[1].split()
            split_dst_2 = dst[2].split()

            if int(split_dst_2[3]) <= int(split_dst_1[3]):
                logging.error('Discrepancy:\t{0} - {1} from {2}\t{3} - {4} from {5}\t{6:>7} - {7} from {8}'.
                              format(split_dst_0[2], split_dst_0[3], split_dst_0[-1],
                                     split_dst_1[0], split_dst_1[3], split_dst_1[-2],
                                     split_dst_2[0], split_dst_2[3], split_dst_2[-2]))

        if 'PSL-E-SYNTAX' in st:
            psl_id = file.index(st)
	    stsplit = st.split(":")
#	    print (" ".join(stsplit))
            logging.error('found SYNTAX error {}'.format((" ".join(stsplit[1:])), file[psl_id].strip('\n')))

        if 'PSL-E-MISMATCH' in st:
            psl_id = file.index(st)
	    stsplit = st.split(":")
#	    print (" ".join(stsplit))
            logging.error('found MISMATCH error {}'.format((" ".join(stsplit[1:])), file[psl_id].strip('\n')))

        if 'PSL-E-ACCESS' in st:
            psl_id = file.index(st)
	    stsplit = st.split(":")
#	    print (" ".join(stsplit))
            logging.error('found ACCESS error {}'.format((" ".join(stsplit[1:])), file[psl_id].strip('\n')))

        if 'PSL-E-RECNOFL' in st:
            psl_id = file.index(st)
	    stsplit = st.split(",")
#	    print (" ".join(stsplit))
            logging.error('found RECNOFL error {}'.format((" ".join(stsplit[3:])), file[psl_id].strip('\n')))
        if 'PSL-W-SCOPE' in st:
            psl_id = file.index(st)
	    stsplit = st.split(" ")
#	    print (" ".join(stsplit[0:]))
            logging.warning('found SCOPE warning {}'.format((" ".join(stsplit[1:])), file[psl_id].strip('\n')))

	if 'PSL-I-LIST' in st:
            psl_id = file.index(st)
            if int(st.split()[1]) > 0:
                logging.error('Was found {} syntax error(s) {}'.format(st.split()[1], file[psl_id + 1].strip('\n')))
            elif int(st.split()[3]) > 0:
                logging.warning('Was found {} warning(s) {}'.format(st.split()[3], file[psl_id + 1].strip('\n')))
            elif int(st.split()[5]) > 0:
                logging.info('Was found {} informational message(s) {}'.format(st.split()[5], file[psl_id + 1].strip('\n')))



        if 'GTM-E' in st:
            logging.error('Was found error GTM in file {0}'.format(st))


def main():
    if len(list_files) == 0:
        logging.error('Files not found.')
    else:
        for f in list_files:
            logging.info('Read file {0}'.format(f))
            o_file = read_file(f)
            if o_file:
                check(o_file)
            else:
                logging.warning('The file was not checked, no line - "PB Server not restarted".')



if __name__ == '__main__':
    main()