// PathVisio,
// a tool for data visualization and analysis using Biological Pathways
// Copyright 2006-2009 BiGCaT Bioinformatics
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

package org.bridgedb.file;

import java.io.Reader;
import java.io.InputStreamReader;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.IOException;

import java.net.URLConnection;
import java.net.URL;

import org.bridgedb.IDMapperException;


/**
 * Class for reading ID mapping data from delimited text file
 * @author gjj
 */
public class IDMappingReaderFromText extends IDMappingReaderFromDelimiterBufferedReader {
    private static int msConnectionTimeout = 2000;

    protected final URL url;

    public IDMappingReaderFromText(final URL url,
            final char[] dataSourceDelimiters) throws IDMapperException {
        this(url, dataSourceDelimiters, null);
    }

    public IDMappingReaderFromText(final URL url,
            final char[] dataSourceDelimiters,
            final char[] regExIDDelimiter) throws IDMapperException {
        this(url, dataSourceDelimiters, regExIDDelimiter, false);
    }

    public IDMappingReaderFromText(final URL url,
            final char[] dataSourceDelimiters,
            final char[] regExIDDelimiter,
            final boolean transitivity) throws IDMapperException {
        this(url, strs2regex(dataSourceDelimiters), strs2regex(regExIDDelimiter), transitivity);
    }

    public IDMappingReaderFromText(final URL url,
            final String regExDataSourceDelimiter) throws IDMapperException {
        this(url, regExDataSourceDelimiter, null);
    }

    public IDMappingReaderFromText(final URL url,
            final String regExDataSourceDelimiter,
            final String regExIDDelimiter) throws IDMapperException {
        this(url, regExDataSourceDelimiter, regExIDDelimiter, false);
    }

    public IDMappingReaderFromText(final URL url,
            final String regExDataSourceDelimiter,
            final String regExIDDelimiter,
            final boolean transitivity) throws IDMapperException {
        super(getReader(url), regExDataSourceDelimiter,
                regExIDDelimiter, transitivity); 
        
        this.url = url;
    }

    public void setDataSourceDelimiters(final char[] dataSourceDelimiters) throws IDMapperException {
        resetReader();
        regExDataSourceDelimiter = strs2regex(dataSourceDelimiters);
        dsValid = false;
        idMappingValid = false;
    }

    public void setIDDelimiters(final char[] idDelimiters) throws IDMapperException {
        resetReader();
        regExIDDelimiter = strs2regex(idDelimiters);
        idMappingValid = false;
    }

    // reset the stream after changing
    protected void resetReader() throws IDMapperException {
        reader = getReader(url);
    }

    protected static String strs2regex(final char[] chs) {
        if (chs==null || chs.length==0) {
            return null;
        }

        StringBuilder regex = new StringBuilder();
        int n = chs.length;
        if (n>0) {
            regex.append("[");
            for (int i=0; i<n; i++) {
                regex.append("\\0"+Integer.toOctalString(chs[i]));
            }
            regex.append("]");
        }

        return regex.toString();
    }

    private static BufferedReader getReader(URL url) throws IDMapperException {
        try {
            InputStream inputStream = getInputStream(url);
            Reader fin = new InputStreamReader(inputStream);
            return new BufferedReader(fin);
        } catch(IOException e) {
            throw new IDMapperException(e);
        }
    }

    protected static InputStream getInputStream(URL source) throws IOException {
		URLConnection uc = source.openConnection();
		uc.setUseCaches(false); // don't use a cached page
		uc.setConnectTimeout(msConnectionTimeout); // set timeout for connection
        return uc.getInputStream();
    }

}
