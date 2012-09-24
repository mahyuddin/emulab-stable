/*
 * Copyright (c) 2010-2011 University of Utah and the Flux Group.
 * 
 * {{{EMULAB-LICENSE
 * 
 * This file is part of the Emulab network testbed software.
 * 
 * This file is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 * 
 * This file is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
 * License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this file.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * }}}
 */
#include    <unistd.h>

#ifdef USE_SSL
#include    <openssl/ssl.h>
#include    <openssl/bio.h>
#include    <openssl/x509v3.h>
#include    <openssl/rand.h>
#include    <openssl/err.h>
#endif

/* XXX hack: default minimum upload speed (MB/sec); used to compute timeouts */
#define MIN_UPLOAD_RATE	(1024 * 1024)

#define	MAX_BUFSIZE	(1024 * 1024)
#define	MAX_TCP_BYTES	(64 * 1024)

#define CONN_SOCKET	1
#define CONN_SSL	2

typedef struct {
	short ctype;
	short maxio;
	union {
		int sockfd;
#ifdef USE_SSL
		struct {
			SSL *ssl;
			SSL_CTX *ctx;
		} sslstate;
#endif
	} desc;
} conn;

extern conn *conn_accept_tcp(int sock, struct in_addr *client);
extern conn *conn_open(in_addr_t addr, in_port_t port, int usessl);
extern int conn_read(conn *conn, void *buf, int num);
extern int conn_write(conn *conn, const void *buf, int num);
extern int conn_close(conn *conn);

#ifdef USE_SSL
void init_OpenSSL();
int seed_prng(int bytes);
int pem_passwd_cb(char *buf, int size, int flag, void *userdata);
int verify_callback(int ok, X509_STORE_CTX * store);
long post_connection_check(SSL * ssl, char *host);
#endif
